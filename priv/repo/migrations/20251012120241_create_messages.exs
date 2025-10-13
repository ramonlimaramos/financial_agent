defmodule FinancialAgent.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "SET statement_timeout TO 10"

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :content, :text, null: false
      add :tool_calls, :jsonb
      add :tokens_used, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:messages, [:conversation_id], concurrently: true)

    execute """
    CREATE TYPE message_role AS ENUM ('user', 'assistant', 'system', 'tool')
    """

    execute "ALTER TABLE messages ALTER COLUMN role TYPE message_role USING role::message_role"
  end

  def down do
    execute "ALTER TABLE messages ALTER COLUMN role TYPE text"
    execute "DROP TYPE message_role"
    drop table(:messages)
  end
end
