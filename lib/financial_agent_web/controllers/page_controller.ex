defmodule FinancialAgentWeb.PageController do
  use FinancialAgentWeb, :controller

  alias FinancialAgent.Accounts

  def home(conn, _params) do
    user_id = get_session(conn, :user_id)

    case user_id do
      nil ->
        # User not logged in - show login page
        render(conn, :home,
          layout: false,
          user: nil,
          google_connected: false,
          hubspot_connected: false
        )

      user_id ->
        # User logged in - check credentials
        google_connected = has_credential?(user_id, "google")
        hubspot_connected = has_credential?(user_id, "hubspot")
        user = Accounts.get_user(user_id)

        render(conn, :home,
          layout: false,
          user: user,
          google_connected: google_connected,
          hubspot_connected: hubspot_connected
        )
    end
  end

  defp has_credential?(user_id, provider) do
    case Accounts.get_credential(user_id, provider) do
      nil -> false
      _credential -> true
    end
  end
end
