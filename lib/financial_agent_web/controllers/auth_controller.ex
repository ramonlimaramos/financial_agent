defmodule FinancialAgentWeb.AuthController do
  use FinancialAgentWeb, :controller

  plug Ueberauth

  alias FinancialAgent.Accounts
  alias FinancialAgent.Workers.{GmailSyncWorker, HubSpotSyncWorker}

  require Logger

  @doc """
  Initiates OAuth flow by redirecting to the provider.
  This is handled automatically by Ueberauth.
  """
  def request(conn, %{"provider" => _provider}) do
    # Ueberauth handles the redirect
    conn
  end

  @doc """
  Handles OAuth callback from the provider.

  Creates or updates user and credentials, then enqueues sync jobs.
  """
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
end
