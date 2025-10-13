defmodule FinancialAgent.Instructions.Instruction do
  @moduledoc """
  Schema for user-defined instructions that trigger automatically on events.

  Instructions allow users to set rules like:
  - "When someone mentions 'pricing', send them our pricing doc link"
  - "When I receive an email from a VIP contact, notify me immediately"
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FinancialAgent.Accounts.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          trigger_type: String.t(),
          condition_text: String.t(),
          action_text: String.t(),
          is_active: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @trigger_types ["new_email", "new_contact", "scheduled"]
  @fields [:user_id, :trigger_type, :condition_text, :action_text, :is_active]
  @required_fields [:user_id, :trigger_type, :condition_text, :action_text]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "instructions" do
    field :trigger_type, :string
    field :condition_text, :string
    field :action_text, :string
    field :is_active, :boolean, default: true

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an instruction.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_length(:condition_text, min: 5, max: 5000)
    |> validate_length(:action_text, min: 5, max: 5000)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid trigger types.
  """
  @spec trigger_types() :: [String.t()]
  def trigger_types, do: @trigger_types
end
