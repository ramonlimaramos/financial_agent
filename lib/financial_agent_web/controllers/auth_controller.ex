defmodule FinancialAgentWeb.AuthController do
  use FinancialAgentWeb, :controller

  plug Ueberauth

  alias FinancialAgent.Accounts
  alias FinancialAgent.OAuth.HubSpot, as: HubSpotOAuth
  alias FinancialAgent.Workers.{GmailSyncWorker, HubSpotSyncWorker}

  require Logger

  @doc """
  Initiates OAuth flow by redirecting to the provider.
  For Google, this is handled by Ueberauth.
  For HubSpot, we handle it directly since there's no Ueberauth strategy.
  """
  def request(conn, %{"provider" => "hubspot"}) do
    redirect_uri = unverified_url(conn, "/auth/hubspot/callback")
    state = generate_state()

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: HubSpotOAuth.authorize_url(redirect_uri, state))
  end

  def request(conn, %{"provider" => _provider}) do
    # Ueberauth handles Google redirect
    conn
  end

  @doc """
  Handles OAuth callback from the provider.

  Creates or updates user and credentials, then enqueues sync jobs.
  """
  def callback(conn, %{"provider" => "hubspot", "code" => code} = params) do
    stored_state = get_session(conn, :oauth_state)
    received_state = Map.get(params, "state")

    # Verify CSRF state
    if stored_state != received_state do
      Logger.error("HubSpot OAuth state mismatch")

      conn
      |> put_flash(:error, "Authentication failed: invalid state")
      |> redirect(to: "/")
    else
      handle_hubspot_callback(conn, code)
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
  Logs out the current user.
  """
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Successfully logged out.")
    |> redirect(to: "/")
  end

  # Private functions

  defp get_or_create_user(%{info: %{email: email}}) when is_binary(email) do
    Accounts.get_or_create_user(email)
  end

  defp get_or_create_user(_auth) do
    {:error, :no_email}
  end

  defp store_credential(user, provider, auth) do
    attrs = %{
      provider: provider,
      access_token: get_access_token(auth),
      refresh_token: get_refresh_token(auth),
      expires_at: get_expires_at(auth)
    }

    Accounts.store_credential(user, attrs)
  end

  defp get_access_token(%{credentials: %{token: token}}) when is_binary(token), do: token
  defp get_access_token(_), do: nil

  defp get_refresh_token(%{credentials: %{refresh_token: token}}) when is_binary(token), do: token
  defp get_refresh_token(_), do: nil

  defp get_expires_at(%{credentials: %{expires_at: expires_at}}) when not is_nil(expires_at) do
    case DateTime.from_unix(expires_at) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp get_expires_at(_), do: nil

  defp enqueue_sync_jobs(user, "google") do
    case GmailSyncWorker.new(%{user_id: user.id}) |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Enqueued Gmail sync job for user #{user.id}")
        {:ok, [job]}

      {:error, reason} = error ->
        Logger.error("Failed to enqueue Gmail sync job: #{inspect(reason)}")
        error
    end
  end

  defp enqueue_sync_jobs(user, "hubspot") do
    case HubSpotSyncWorker.new(%{user_id: user.id}) |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Enqueued HubSpot sync job for user #{user.id}")
        {:ok, [job]}

      {:error, reason} = error ->
        Logger.error("Failed to enqueue HubSpot sync job: #{inspect(reason)}")
        error
    end
  end

  defp enqueue_sync_jobs(_user, _provider) do
    Logger.warning("No sync worker configured for provider")
    {:ok, []}
  end

  # HubSpot OAuth helpers

  defp handle_hubspot_callback(conn, code) do
    redirect_uri = unverified_url(conn, "/auth/hubspot/callback")

    case HubSpotOAuth.get_token(code, redirect_uri) do
      {:ok, token_response} ->
        # For HubSpot, we don't get user email from the OAuth response
        # We'll need to fetch it from the user info API or use a default
        # For now, create/get user from session or use a placeholder
        process_hubspot_token(conn, token_response)

      {:error, reason} ->
        Logger.error("HubSpot token exchange failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to authenticate with HubSpot")
        |> redirect(to: "/")
    end
  end

  defp process_hubspot_token(conn, token_response) do
    # TODO: Fetch user email from HubSpot API if needed
    # For now, we'll require the user to be logged in first with Google
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> put_flash(:error, "Please log in with Google first before connecting HubSpot")
        |> redirect(to: "/")

      user_id ->
        store_hubspot_credential(conn, user_id, token_response)
    end
  end

  defp store_hubspot_credential(conn, user_id, token_response) do
    attrs = %{
      provider: "hubspot",
      access_token: token_response["access_token"],
      refresh_token: token_response["refresh_token"],
      expires_at: calculate_expires_at(token_response["expires_in"])
    }

    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: "/")

      user ->
        case Accounts.store_credential(user, attrs) do
          {:ok, _credential} ->
            {:ok, _jobs} = enqueue_sync_jobs(user, "hubspot")

            conn
            |> put_flash(:info, "Successfully connected HubSpot!")
            |> redirect(to: "/")

          {:error, changeset} ->
            Logger.error("Failed to store HubSpot credential: #{inspect(changeset.errors)}")

            conn
            |> put_flash(:error, "Failed to save HubSpot connection")
            |> redirect(to: "/")
        end
    end
  end

  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  defp calculate_expires_at(_), do: nil

  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
