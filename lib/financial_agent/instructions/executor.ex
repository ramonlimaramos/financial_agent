defmodule FinancialAgent.Instructions.Executor do
  @moduledoc """
  Executes actions specified in matched instructions.

  When an instruction matches an event, this module interprets the action_text
  and calls the appropriate tools via the ToolExecutor.
  """

  alias FinancialAgent.AI.{LLMClient, ToolExecutor}
  alias FinancialAgent.Instructions.Instruction
  alias FinancialAgent.Instructions.Matcher

  require Logger

  @type execution_context :: %{
          user_id: Ecto.UUID.t(),
          event_data: Matcher.event_data()
        }

  @type execution_result :: %{
          success: boolean(),
          tool_calls: [map()],
          error: String.t() | nil
        }

  @doc """
  Executes an instruction's action based on the matched event.

  The LLM determines which tool to call and with what arguments based on
  the instruction's action_text and the event data.

  ## Examples

      iex> instruction = %Instruction{action_text: "Send them the pricing doc link"}
      iex> context = %{user_id: user_id, event_data: event}
      iex> execute(instruction, context)
      {:ok, %{success: true, tool_calls: [%{tool: "send_email", ...}]}}
  """
  @spec execute(Instruction.t(), execution_context()) ::
          {:ok, execution_result()} | {:error, term()}
  def execute(instruction, context) do
    Logger.info("Executing instruction #{instruction.id} for user #{context.user_id}")

    prompt = build_execution_prompt(instruction, context.event_data)

    messages = [
      %{
        role: "system",
        content: """
        You are an action executor. Based on the instruction and event, determine what action to take.
        You have access to tools for sending emails, looking up contacts, and scheduling meetings.

        Respond with JSON in this format:
        {
          "action": "tool_name",
          "arguments": {...},
          "reasoning": "why this action"
        }

        If no action is needed, respond with:
        {"action": "none", "reasoning": "explanation"}
        """
      },
      %{role: "user", content: prompt}
    ]

    case LLMClient.chat_completion(messages, model: "gpt-4o", temperature: 0.3, max_tokens: 500) do
      {:ok, response} ->
        parse_and_execute_action(response, context)

      {:error, reason} ->
        Logger.error("LLM error during instruction execution: #{inspect(reason)}")
        {:error, {:llm_error, reason}}
    end
  end

  defp build_execution_prompt(instruction, event_data) do
    """
    ## Instruction Action
    #{instruction.action_text}

    ## Event That Triggered This
    Type: #{event_data.type}
    #{if event_data.subject, do: "Subject: #{event_data.subject}\n", else: ""}#{if event_data.from, do: "From: #{event_data.from}\n", else: ""}Content: #{String.slice(event_data.content, 0, 500)}

    What action should be taken? If you need to send an email, use the send_email tool.
    If you need to look up contact information, use the get_hubspot_contact tool.
    """
  end

  defp parse_and_execute_action(response, context) do
    content = response.content || ""

    case Jason.decode(content) do
      {:ok, %{"action" => "none"}} ->
        {:ok, %{success: true, tool_calls: [], error: nil}}

      {:ok, %{"action" => action, "arguments" => arguments}} when action != "none" ->
        execute_tool_call(action, arguments, context)

      {:ok, %{"action" => action}} when action != "none" ->
        # No arguments provided, try with empty map
        execute_tool_call(action, %{}, context)

      {:error, _reason} ->
        Logger.warning("Failed to parse action from LLM response: #{content}")
        {:ok, %{success: false, tool_calls: [], error: "Failed to parse action"}}

      _ ->
        {:ok, %{success: false, tool_calls: [], error: "Unexpected response format"}}
    end
  end

  defp execute_tool_call(tool_name, arguments, context) do
    tool_context = %{
      user_id: context.user_id,
      conversation_id: nil
    }

    case ToolExecutor.execute(tool_name, arguments, tool_context) do
      {:ok, result} ->
        Logger.info("Tool #{tool_name} executed successfully: #{inspect(result)}")

        {:ok,
         %{
           success: true,
           tool_calls: [%{tool: tool_name, arguments: arguments, result: result}],
           error: nil
         }}

      {:error, reason} ->
        Logger.error("Tool execution failed: #{inspect(reason)}")

        {:ok,
         %{
           success: false,
           tool_calls: [],
           error: "Tool execution failed: #{inspect(reason)}"
         }}
    end
  end
end
