defmodule FinancialAgent.Repo.Migrations.CreateTaskMessages do
  use Ecto.Migration

  def change do
    create table(:task_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:task_messages, [:task_id])
    create index(:task_messages, [:task_id, :inserted_at])
  end
end
