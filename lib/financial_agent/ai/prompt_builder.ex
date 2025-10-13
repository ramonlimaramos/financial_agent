defmodule FinancialAgent.AI.PromptBuilder do
  @moduledoc """
  Builds prompts for LLM interactions, including system prompts and RAG context injection.
  """

  @doc """
  Builds the system prompt for the AI assistant.
  """
  @spec build_system_prompt() :: String.t()
  def build_system_prompt do
    """
    You are a helpful AI assistant with access to the user's emails, CRM data, and calendar.
    Your role is to help users manage their business relationships and tasks efficiently.

    You can:
    - Answer questions about emails and contacts
    - Look up contact information from HubSpot
    - Help schedule meetings and manage calendar events
    - Provide insights from past conversations and interactions

    Always be:
    - Concise but complete in your responses
    - Accurate and cite sources when referencing specific information
    - Proactive in suggesting helpful actions
    - Clear when you don't have enough information to answer a question
    """
  end

  @doc """
  Builds a RAG prompt with retrieved context chunks.

  The retrieved chunks are formatted and injected into the prompt as context
  for the LLM to use when answering the user's question.
  """
  @spec build_rag_prompt(String.t(), [map()]) :: [map()]
  def build_rag_prompt(user_query, retrieved_chunks) do
    context_text = format_context_chunks(retrieved_chunks)

    user_message = """
    Context (relevant excerpts from your data):
    #{context_text}

    Question: #{user_query}

    Instructions:
    - Answer based ONLY on the provided context
    - If the context doesn't contain enough information to answer, say so clearly
    - Cite sources naturally (e.g., "In an email from Sara..." or "According to the HubSpot contact...")
    - Be concise but complete
    """

    [
      %{role: "system", content: build_system_prompt()},
      %{role: "user", content: user_message}
    ]
  end

  @doc """
  Builds a simple chat prompt without RAG context.
  """
  @spec build_chat_prompt([map()]) :: [map()]
  def build_chat_prompt(conversation_messages) do
    [%{role: "system", content: build_system_prompt()} | conversation_messages]
  end

  @doc """
  Builds a prompt for tool calling.
  """
  @spec build_tool_prompt(String.t(), [map()]) :: [map()]
  def build_tool_prompt(user_request, available_tools) do
    tools_description = format_tools_description(available_tools)

    system_prompt = """
    #{build_system_prompt()}

    You have access to the following tools:
    #{tools_description}

    When you need to use a tool, request it using the function calling format.
    """

    [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_request}
    ]
  end

  @doc """
  Formats context chunks for inclusion in prompts.
  """
  @spec format_context_chunks([map()]) :: String.t()
  def format_context_chunks([]), do: "No relevant context found."

  def format_context_chunks(chunks) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, idx} ->
      source_info = format_source_info(chunk.source, chunk.metadata)

      """
      [#{idx}] #{source_info}
      #{chunk.content}
      """
    end)
    |> Enum.join("\n---\n")
  end

  defp format_source_info("gmail", metadata) do
    subject = Map.get(metadata, "subject", "Unknown Subject")
    from = Map.get(metadata, "from", "Unknown Sender")
    "Source: Email - #{subject} (from: #{from})"
  end

  defp format_source_info("hubspot", metadata) do
    contact_name = Map.get(metadata, "contact_name", "Unknown Contact")
    "Source: HubSpot Contact - #{contact_name}"
  end

  defp format_source_info("calendar", metadata) do
    event_title = Map.get(metadata, "title", "Unknown Event")
    "Source: Calendar Event - #{event_title}"
  end

  defp format_source_info(source, _metadata), do: "Source: #{source}"

  defp format_tools_description(tools) do
    tools
    |> Enum.map(fn tool ->
      function = tool[:function] || tool["function"]
      name = function[:name] || function["name"]
      description = function[:description] || function["description"]
      "- #{name}: #{description}"
    end)
    |> Enum.join("\n")
  end
end
