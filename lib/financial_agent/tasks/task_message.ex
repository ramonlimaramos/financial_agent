defmodule FinancialAgent.Tasks.TaskMessage do
  @moduledoc """
  Schema for task conversation messages.

  Stores the multi-turn conversation history for a task, including:
  - User messages (input/questions)
  - Agent messages (responses/actions)
  - System messages (state changes/events)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FinancialAgent.Tasks.Task

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ["user", "agent", "system", "tool"]

  @fields [:role, :content, :metadata]
  @required_fields [:role, :content]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          role: String.t() | nil,
          content: String.t() | nil,
          metadata: map() | nil,
          task_id: Ecto.UUID.t() | nil,
          task: Task.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "task_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new task message.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @fields ++ [:task_id])
    |> validate_required(@required_fields ++ [:task_id])
    |> validate_inclusion(:role, @roles)
    |> validate_length(:content, min: 1, max: 10_000)
    |> foreign_key_constraint(:task_id)
  end

  @doc """
  Returns list of valid roles.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles
end
