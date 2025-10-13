defmodule FinancialAgentWeb.AuthController do
  @moduledoc """
  Handles OAuth authentication flows for Google and HubSpot.

  Google OAuth uses Ueberauth strategy, while HubSpot uses a custom
  implementation due to lack of Ueberauth strategy support.
  """

  use FinancialAgentWeb, :controller

  plug :ueberauth_for_google when action in [:request, :callback]

  alias FinancialAgent.Accounts
  alias FinancialAgent.OAuth.HubSpot, as: HubSpotOAuth
  alias FinancialAgent.Workers.{CalendarSyncWorker, GmailSyncWorker, HubSpotSyncWorker}

  require Logger

  @provider_google "google"
  @provider_hubspot "hubspot"
  @callback_path "/auth/hubspot/callback"

  defp ueberauth_for_google(%{params: %{"provider" => @provider_hubspot}} = conn, _opts) do
    conn
  end

  defp ueberauth_for_google(conn, _opts) do
    Ueberauth.call(conn, Ueberauth.init([]))
  end

  @doc """
  Initiates OAuth flow by redirecting to the provider.

  For Google, Ueberauth handles the redirect automatically.
  For HubSpot, generates CSRF state token and redirects to HubSpot authorization URL.
  """
  @spec request(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request(conn, %{"provider" => @provider_hubspot}) do
    redirect_uri = unverified_url(conn, @callback_path)
    state = generate_state()

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: HubSpotOAuth.authorize_url(redirect_uri, state))
  end

  def request(conn, %{"provider" => _provider}) do
    conn
  end

  @doc """
  Handles OAuth callback from the provider.

  Creates or updates user and credentials, then enqueues sync jobs.
  For HubSpot, verifies CSRF state token before processing.
  """
  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(conn, %{"provider" => @provider_hubspot, "code" => code} = params) do
    with {:ok, conn} <- verify_csrf_state(conn, params),
         {:ok, conn} <- handle_hubspot_callback(conn, code) do
      conn
    else
      {:error, :state_mismatch} ->
        Logger.error("HubSpot OAuth state mismatch")

        conn
        |> put_flash(:error, "Authentication failed: invalid state")
        |> redirect(to: "/")

      {:error, :no_user_session} ->
        conn
        |> put_flash(:error, "Please log in with Google first before connecting HubSpot")
        |> redirect(to: "/")

      {:error, :user_not_found} ->
        conn
        |> put_flash(:error, "User not found. Please log in again.")
        |> redirect(to: "/")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "Failed to save HubSpot connection")
        |> redirect(to: "/")

      {:error, reason} ->
        Logger.error("HubSpot OAuth callback failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to authenticate with HubSpot")
        |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, %{"provider" => provider}) do
    Logger.error("Auth callback failure for #{provider}: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Failed to authenticate with #{String.capitalize(provider)}.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    with {:ok, user} <- get_or_create_user(auth),
         {:ok, _credential} <- store_credential(user, provider, auth),
         {:ok, _jobs} <- enqueue_sync_jobs(user, provider) do
      conn
      |> put_session(:user_id, user.id)
      |> put_flash(:info, "Successfully authenticated with #{String.capitalize(provider)}!")
      |> redirect(to: "/")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("Auth callback error: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to authenticate. Please try again.")
        |> redirect(to: "/")

      {:error, reason} ->
        Logger.error("Auth callback error: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to authenticate. Please try again.")
        |> redirect(to: "/")
    end
  end

  @doc """
  Logs out the current user by dropping the session.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Successfully logged out.")
    |> redirect(to: "/")
  end

  # Private functions

  @spec verify_csrf_state(Plug.Conn.t(), map()) ::
          {:ok, Plug.Conn.t()} | {:error, :state_mismatch}
  defp verify_csrf_state(conn, params) do
    stored_state = get_session(conn, :oauth_state)
    received_state = Map.get(params, "state")

    if stored_state == received_state do
      {:ok, conn}
    else
      {:error, :state_mismatch}
    end
  end

  @spec get_or_create_user(map()) :: {:ok, Accounts.User.t()} | {:error, :no_email}
  defp get_or_create_user(%{info: %{email: email}}) when is_binary(email) do
    Accounts.get_or_create_user(email)
  end

  defp get_or_create_user(_auth) do
    {:error, :no_email}
  end

  @spec store_credential(Accounts.User.t(), String.t(), map()) ::
          {:ok, Accounts.Credential.t()} | {:error, Ecto.Changeset.t()}
  defp store_credential(user, provider, auth) do
    attrs = %{
      provider: provider,
      access_token: extract_access_token(auth),
      refresh_token: extract_refresh_token(auth),
      expires_at: extract_expires_at(auth)
    }

    Accounts.store_credential(user, attrs)
  end

  @spec extract_access_token(map()) :: String.t() | nil
  defp extract_access_token(%{credentials: %{token: token}}) when is_binary(token), do: token
  defp extract_access_token(_), do: nil

  @spec extract_refresh_token(map()) :: String.t() | nil
  defp extract_refresh_token(%{credentials: %{refresh_token: token}}) when is_binary(token),
    do: token

  defp extract_refresh_token(_), do: nil

  @spec extract_expires_at(map()) :: DateTime.t() | nil
  defp extract_expires_at(%{credentials: %{expires_at: expires_at}})
       when not is_nil(expires_at) do
    case DateTime.from_unix(expires_at) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp extract_expires_at(_), do: nil

  @spec enqueue_sync_jobs(Accounts.User.t(), String.t()) :: {:ok, list()} | {:error, term()}
  defp enqueue_sync_jobs(user, @provider_google) do
    with {:ok, gmail_jobs} <- enqueue_worker(user, GmailSyncWorker, "Gmail"),
         {:ok, calendar_jobs} <- enqueue_worker(user, CalendarSyncWorker, "Calendar") do
      {:ok, gmail_jobs ++ calendar_jobs}
    end
  end

  defp enqueue_sync_jobs(user, @provider_hubspot) do
    enqueue_worker(user, HubSpotSyncWorker, "HubSpot")
  end

  defp enqueue_sync_jobs(_user, provider) do
    Logger.warning("No sync worker configured for provider: #{provider}")
    {:ok, []}
  end

  @spec enqueue_worker(Accounts.User.t(), module(), String.t()) ::
          {:ok, list()} | {:error, term()}
  defp enqueue_worker(user, worker_module, worker_name) do
    case worker_module.new(%{user_id: user.id}) |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Enqueued #{worker_name} sync job for user #{user.id}")
        {:ok, [job]}

      {:error, reason} = error ->
        Logger.error("Failed to enqueue #{worker_name} sync job: #{inspect(reason)}")
        error
    end
  end

  # HubSpot OAuth helpers

  @spec handle_hubspot_callback(Plug.Conn.t(), String.t()) ::
          {:ok, Plug.Conn.t()} | {:error, term()}
  defp handle_hubspot_callback(conn, code) do
    redirect_uri = unverified_url(conn, @callback_path)
    Logger.info("HubSpot callback - exchanging code for token")

    with {:ok, token_response} <- HubSpotOAuth.get_token(code, redirect_uri),
         {:ok, conn} <- process_hubspot_token(conn, token_response) do
      Logger.info("HubSpot token exchange successful")
      {:ok, conn}
    else
      {:error, reason} = error ->
        Logger.error("HubSpot token exchange failed: #{inspect(reason)}")
        error
    end
  end

  @spec process_hubspot_token(Plug.Conn.t(), map()) :: {:ok, Plug.Conn.t()} | {:error, term()}
  defp process_hubspot_token(conn, token_response) do
    user_id = get_session(conn, :user_id)
    Logger.info("Processing HubSpot token")

    case user_id do
      nil ->
        Logger.warning("No user_id in session for HubSpot OAuth")
        {:error, :no_user_session}

      user_id ->
        Logger.info("Storing HubSpot credential for user #{user_id}")
        store_hubspot_credential(conn, user_id, token_response)
    end
  end

  @spec store_hubspot_credential(Plug.Conn.t(), String.t(), map()) ::
          {:ok, Plug.Conn.t()} | {:error, term()}
  defp store_hubspot_credential(conn, user_id, token_response) do
    attrs = %{
      provider: @provider_hubspot,
      access_token: token_response["access_token"],
      refresh_token: token_response["refresh_token"],
      expires_at: calculate_expires_at(token_response["expires_in"])
    }

    with {:ok, user} <- fetch_user(user_id),
         {:ok, credential} <- Accounts.store_credential(user, attrs),
         {:ok, _jobs} <- enqueue_sync_jobs(user, @provider_hubspot) do
      Logger.info("Successfully stored HubSpot credential #{credential.id}")

      conn
      |> put_flash(:info, "Successfully connected HubSpot!")
      |> redirect(to: "/")
      |> then(&{:ok, &1})
    else
      {:error, :user_not_found} ->
        Logger.error("User #{user_id} not found in database")
        {:error, :user_not_found}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("Failed to store HubSpot credential: #{inspect(changeset.errors)}")
        {:error, changeset}

      {:error, reason} = error ->
        Logger.error("Failed to store HubSpot credential: #{inspect(reason)}")
        error
    end
  end

  @spec fetch_user(String.t()) :: {:ok, Accounts.User.t()} | {:error, :user_not_found}
  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  @spec calculate_expires_at(integer() | nil) :: DateTime.t() | nil
  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  defp calculate_expires_at(_), do: nil

  @spec generate_state() :: String.t()
  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
