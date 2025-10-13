defmodule FinancialAgent.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "SET statement_timeout TO 10"

    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:user_id, :updated_at], concurrently: true)
  end

  def down do
    drop table(:conversations)
  end
end
