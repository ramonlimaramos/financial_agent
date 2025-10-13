defmodule FinancialAgent.Tasks.Task do
  @moduledoc """
  Schema for stateful tasks that require multi-turn agent workflows.

  Tasks represent complex operations that may require multiple steps,
  user input, or external API calls. Each task maintains its own
  conversation history via TaskMessage records.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FinancialAgent.Accounts.User
  alias FinancialAgent.Instructions.Instruction
  alias FinancialAgent.Tasks.TaskMessage

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @task_types ["schedule_meeting", "compose_email", "research", "data_analysis", "custom"]
  @statuses ["pending", "in_progress", "waiting_for_input", "completed", "failed", "cancelled"]

  @fields [:title, :description, :task_type, :status, :context, :result, :error, :completed_at]
  @required_fields [:title, :task_type]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          task_type: String.t() | nil,
          status: String.t() | nil,
          context: map() | nil,
          result: map() | nil,
          error: String.t() | nil,
          completed_at: DateTime.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_instruction_id: Ecto.UUID.t() | nil,
          parent_instruction: Instruction.t() | Ecto.Association.NotLoaded.t() | nil,
          messages: [TaskMessage.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :task_type, :string
    field :status, :string, default: "pending"
    field :context, :map, default: %{}
    field :result, :map
    field :error, :string
    field :completed_at, :utc_datetime

    belongs_to :user, User
    belongs_to :parent_instruction, Instruction
    has_many :messages, TaskMessage

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new task.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, @fields ++ [:user_id, :parent_instruction_id])
    |> validate_required(@required_fields ++ [:user_id])
    |> validate_inclusion(:task_type, @task_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:title, min: 3, max: 255)
    |> validate_length(:description, max: 5000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:parent_instruction_id)
  end

  @doc """
  Creates a changeset for updating task status.
  """
  @spec status_changeset(t(), String.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(task, new_status, attrs \\ %{}) do
    task
    |> cast(attrs, [:status, :result, :error, :completed_at])
    |> put_change(:status, new_status)
    |> maybe_set_completed_at(new_status)
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Returns list of valid task types.
  """
  @spec task_types() :: [String.t()]
  def task_types, do: @task_types

  @doc """
  Returns list of valid statuses.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp maybe_set_completed_at(changeset, "completed") do
    put_change(changeset, :completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp maybe_set_completed_at(changeset, "failed") do
    put_change(changeset, :completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp maybe_set_completed_at(changeset, "cancelled") do
    put_change(changeset, :completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp maybe_set_completed_at(changeset, _status), do: changeset
end
