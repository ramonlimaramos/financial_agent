defmodule FinancialAgent.Repo.Migrations.CreateInstructions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "SET statement_timeout TO 10"

    create table(:instructions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :trigger_type, :string, null: false
      add :condition_text, :text, null: false
      add :action_text, :text, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:instructions, [:user_id], concurrently: true)
    create index(:instructions, [:is_active], concurrently: true)
    create index(:instructions, [:user_id, :trigger_type, :is_active], concurrently: true)
  end

  def down do
    drop_if_exists table(:instructions)
  end
end
