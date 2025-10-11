defmodule FinancialAgent.Repo do
  use Ecto.Repo,
    otp_app: :financial_agent,
    adapter: Ecto.Adapters.Postgres
end
