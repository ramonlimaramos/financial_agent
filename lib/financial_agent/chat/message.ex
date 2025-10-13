defmodule FinancialAgent.Chat.Message do
  @moduledoc """
  Message schema for individual messages within conversations.
  Supports user, assistant, system, and tool messages following OpenAI format.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FinancialAgent.Chat.Conversation

  @type role :: :user | :assistant | :system | :tool
  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          conversation_id: Ecto.UUID.t(),
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t(),
          role: role(),
          content: String.t(),
          tool_calls: map() | nil,
          tokens_used: integer() | nil,
          inserted_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, Ecto.Enum, values: [:user, :assistant, :system, :tool]
    field :content, :string
    field :tool_calls, :map
    field :tokens_used, :integer
    field :conversation_id, :binary_id

    belongs_to :conversation, Conversation, define_field: false

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset for creating a new message.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :tool_calls, :tokens_used])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, [:user, :assistant, :system, :tool])
    |> foreign_key_constraint(:conversation_id)
  end

  @doc """
  Converts message or list of messages to OpenAI API format.
  """
  @spec to_openai_format(t()) :: map()
  @spec to_openai_format([t()]) :: [map()]
  def to_openai_format(%__MODULE__{} = message) do
    base = %{
      role: to_string(message.role),
      content: message.content
    }

    if message.tool_calls do
      Map.put(base, :tool_calls, message.tool_calls)
    else
      base
    end
  end

  def to_openai_format(messages) when is_list(messages) do
    Enum.map(messages, &to_openai_format/1)
  end
end
