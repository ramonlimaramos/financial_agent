defmodule FinancialAgent.Chat do
  @moduledoc """
  Context for managing conversations and messages.
  """

  import Ecto.Query
  alias FinancialAgent.Repo
  alias FinancialAgent.Chat.{Conversation, Message}

  @doc """
  Creates a new conversation for a user.
  """
  @spec create_conversation(Ecto.UUID.t(), map()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def create_conversation(user_id, attrs \\ %{}) do
    attrs = Map.put(attrs, :user_id, user_id)

    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds a message to a conversation.
  """
  @spec add_message(Ecto.UUID.t(), Message.role(), String.t(), map()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def add_message(conversation_id, role, content, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:conversation_id, conversation_id)
      |> Map.put(:role, role)
      |> Map.put(:content, content)

    result =
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()

    with {:ok, message} <- result do
      update_conversation_timestamp(conversation_id)
      {:ok, message}
    end
  end

  @doc """
  Gets a conversation with all its messages preloaded.
  """
  @spec get_conversation_with_messages(Ecto.UUID.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found}
  def get_conversation_with_messages(conversation_id) do
    query =
      from c in Conversation,
        where: c.id == ^conversation_id,
        preload: [messages: ^from(m in Message, order_by: [asc: m.inserted_at])]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Lists recent conversations for a user.
  """
  @spec list_user_conversations(Ecto.UUID.t(), keyword()) :: [Conversation.t()]
  def list_user_conversations(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(c in Conversation,
      where: c.user_id == ^user_id,
      order_by: [desc: c.updated_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Updates a conversation's title.
  """
  @spec update_conversation_title(Ecto.UUID.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def update_conversation_title(conversation_id, title) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :not_found}

      conversation ->
        conversation
        |> Conversation.changeset(%{title: title})
        |> Repo.update()
    end
  end

  @doc """
  Auto-generates and updates conversation title from first user message.
  """
  @spec auto_generate_title(Ecto.UUID.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def auto_generate_title(conversation_id, first_message) do
    title = Conversation.generate_title(first_message)
    update_conversation_title(conversation_id, title)
  end

  @doc """
  Gets recent messages for a conversation with a limit.
  Useful for managing context window size.
  """
  @spec get_recent_messages(Ecto.UUID.t(), integer()) :: [Message.t()]
  def get_recent_messages(conversation_id, limit) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Deletes a conversation and all its messages.
  """
  @spec delete_conversation(Ecto.UUID.t()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def delete_conversation(conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      nil -> {:error, :not_found}
      conversation -> Repo.delete(conversation)
    end
  end

  defp update_conversation_timestamp(conversation_id) do
    from(c in Conversation,
      where: c.id == ^conversation_id
    )
    |> Repo.update_all(set: [updated_at: DateTime.utc_now()])
  end
end
