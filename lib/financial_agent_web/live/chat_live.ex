defmodule FinancialAgentWeb.ChatLive do
  use FinancialAgentWeb, :live_view

  alias FinancialAgent.Chat
  alias Phoenix.PubSub

  @impl true
  def mount(_params, session, socket) do
    user_id = get_user_id_from_session(session)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:streaming, false)
      |> assign(:current_assistant_message, "")

    case user_id do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to access the chat")
         |> redirect(to: "/")}

      user_id ->
        case verify_user_credentials(user_id) do
          :ok ->
            if connected?(socket) do
              conversation_id = create_or_load_conversation(user_id)
              subscribe_to_conversation(conversation_id)

              {:ok,
               socket
               |> assign(:conversation_id, conversation_id)
               |> load_conversation_messages()}
            else
              {:ok, socket}
            end

          {:error, :missing_google} ->
            {:ok,
             socket
             |> put_flash(:error, "Please connect your Google account first")
             |> redirect(to: "/auth/google")}

          {:error, :missing_hubspot} ->
            {:ok,
             socket
             |> put_flash(:error, "Please connect your HubSpot account first")
             |> redirect(to: "/auth/hubspot")}
        end
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    if String.trim(text) != "" do
      conversation_id = socket.assigns.conversation_id
      user_id = socket.assigns.user_id

      {:ok, user_message} = Chat.add_message(conversation_id, :user, text)

      socket =
        socket
        |> assign(:input, "")
        |> assign(:streaming, true)
        |> assign(:current_assistant_message, "")
        |> update(:messages, fn messages -> messages ++ [user_message] end)

      Task.start(fn ->
        process_user_message(conversation_id, user_id, text)
      end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => text}, socket) do
    {:noreply, assign(socket, :input, text)}
  end

  @impl true
  def handle_info({:stream_chunk, chunk}, socket) do
    current = socket.assigns.current_assistant_message
    updated = current <> chunk

    socket =
      socket
      |> assign(:current_assistant_message, updated)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_complete, final_message}, socket) do
    socket =
      socket
      |> assign(:streaming, false)
      |> assign(:current_assistant_message, "")
      |> update(:messages, fn messages -> messages ++ [final_message] end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_error, error}, socket) do
    socket =
      socket
      |> put_flash(:error, "Error: #{inspect(error)}")
      |> assign(:streaming, false)
      |> assign(:current_assistant_message, "")

    {:noreply, socket}
  end

  defp create_or_load_conversation(user_id) do
    conversations = Chat.list_user_conversations(user_id, limit: 1)

    case conversations do
      [conversation | _] ->
        conversation.id

      [] ->
        {:ok, conversation} = Chat.create_conversation(user_id)
        conversation.id
    end
  end

  defp load_conversation_messages(socket) do
    conversation_id = socket.assigns.conversation_id

    case Chat.get_conversation_with_messages(conversation_id) do
      {:ok, conversation} ->
        assign(socket, :messages, conversation.messages)

      {:error, _} ->
        assign(socket, :messages, [])
    end
  end

  defp subscribe_to_conversation(conversation_id) do
    PubSub.subscribe(FinancialAgent.PubSub, "chat:#{conversation_id}")
  end

  defp process_user_message(conversation_id, user_id, text) do
    alias FinancialAgent.AI.LLMClient
    alias FinancialAgent.AI.PromptBuilder
    alias FinancialAgent.RAG.Retrieval

    case Retrieval.search_similar(user_id, text, limit: 5) do
      {:ok, retrieved_chunks} ->
        messages = PromptBuilder.build_rag_prompt(text, retrieved_chunks)

        case LLMClient.chat_completion_stream(messages) do
          {:ok, stream} ->
            stream_to_conversation(stream, conversation_id)

          {:error, reason} ->
            broadcast_error(conversation_id, reason)
        end

      {:error, reason} ->
        broadcast_error(conversation_id, reason)
    end
  end

  defp stream_to_conversation(stream, conversation_id) do
    accumulated =
      Enum.reduce(stream, "", fn chunk, acc ->
        case chunk do
          {:content, content} ->
            broadcast_chunk(conversation_id, content)
            acc <> content

          _ ->
            acc
        end
      end)

    # Only save and broadcast if we have content
    if String.trim(accumulated) != "" do
      case Chat.add_message(conversation_id, :assistant, accumulated) do
        {:ok, message} ->
          broadcast_complete(conversation_id, message)

        {:error, _changeset} ->
          # If saving fails, broadcast error
          broadcast_error(conversation_id, "Failed to save assistant response")
      end
    else
      # No content received from LLM - broadcast error
      broadcast_error(conversation_id, "No response received from AI")
    end
  end

  defp broadcast_chunk(conversation_id, chunk) do
    PubSub.broadcast(
      FinancialAgent.PubSub,
      "chat:#{conversation_id}",
      {:stream_chunk, chunk}
    )
  end

  defp broadcast_complete(conversation_id, message) do
    PubSub.broadcast(
      FinancialAgent.PubSub,
      "chat:#{conversation_id}",
      {:stream_complete, message}
    )
  end

  defp broadcast_error(conversation_id, error) do
    PubSub.broadcast(
      FinancialAgent.PubSub,
      "chat:#{conversation_id}",
      {:stream_error, error}
    )
  end

  defp get_user_id_from_session(session) do
    Map.get(session, "user_id")
  end

  defp verify_user_credentials(user_id) do
    alias FinancialAgent.Accounts

    google_credential = Accounts.get_credential(user_id, "google")
    hubspot_credential = Accounts.get_credential(user_id, "hubspot")

    cond do
      is_nil(google_credential) -> {:error, :missing_google}
      is_nil(hubspot_credential) -> {:error, :missing_hubspot}
      true -> :ok
    end
  end

  defp message_class(:user), do: "bg-blue-100 shadow-sm"
  defp message_class(:assistant), do: "bg-white shadow-sm"
  defp message_class(_), do: "bg-gray-100 shadow-sm"
end
