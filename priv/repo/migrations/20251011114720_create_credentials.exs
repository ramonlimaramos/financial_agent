defmodule FinancialAgent.Repo.Migrations.CreateCredentials do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :access_token_hash, :binary, null: false
      add :refresh_token_hash, :binary
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:credentials, [:user_id])
    create unique_index(:credentials, [:user_id, :provider])
  end
end
