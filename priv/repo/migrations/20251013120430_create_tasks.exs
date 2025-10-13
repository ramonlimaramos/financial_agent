defmodule FinancialAgent.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :task_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :context, :map, default: %{}
      add :result, :map
      add :error, :text

      add :parent_instruction_id,
          references(:instructions, type: :binary_id, on_delete: :nilify_all)

      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
    create index(:tasks, [:task_type])
    create index(:tasks, [:parent_instruction_id])
    create index(:tasks, [:user_id, :status])
  end
end
