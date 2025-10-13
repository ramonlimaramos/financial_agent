defmodule FinancialAgent.Chat.Conversation do
  @moduledoc """
  Conversation schema for chat sessions between users and the AI assistant.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FinancialAgent.Accounts.User
  alias FinancialAgent.Chat.Message

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          title: String.t() | nil,
          messages: [Message.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :title, :string
    field :user_id, :binary_id

    belongs_to :user, User, define_field: false
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new conversation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:user_id, :title])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Generates a conversation title from the first user message.
  """
  @spec generate_title(String.t()) :: String.t()
  def generate_title(first_message) do
    first_message
    |> String.slice(0, 60)
    |> then(fn text ->
      if String.length(first_message) > 60 do
        text <> "..."
      else
        text
      end
    end)
  end
end
