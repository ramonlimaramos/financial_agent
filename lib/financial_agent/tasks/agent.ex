defmodule FinancialAgent.Tasks.Agent do
  @moduledoc """
  LLM-powered agent for executing stateful tasks.

  The agent:
  1. Analyzes the task and its conversation history
  2. Determines the next action to take
  3. Calls appropriate tools or requests user input
  4. Updates task state based on results
  """

  require Logger

  alias FinancialAgent.{Tasks}
  alias FinancialAgent.AI.{LLMClient, ToolExecutor}
  alias FinancialAgent.Tasks.{Task, StateMachine}

  @doc """
  Executes a single step of a task.

  Returns:
  - `{:ok, :completed, result}` - Task completed successfully
  - `{:ok, :waiting_for_input, message}` - Needs user input
  - `{:ok, :continue}` - Progress made, continue processing
  - `{:error, reason}` - Execution failed
  """
  @spec execute_step(Task.t()) ::
          {:ok, :completed, map()}
          | {:ok, :waiting_for_input, String.t()}
          | {:ok, :continue}
          | {:error, term()}
  def execute_step(task) do
    with :ok <- StateMachine.validate_transition(task, "in_progress"),
         {:ok, _task} <- Tasks.update_task_status(task, "in_progress"),
         conversation <- Tasks.get_task_conversation(task.id),
         {:ok, decision} <- analyze_and_decide(task, conversation),
         {:ok, result} <- execute_decision(task, decision) do
      handle_execution_result(task, result)
    else
      {:error, :invalid_transition} ->
        Logger.warning("Invalid transition for task #{task.id}: #{task.status} -> in_progress")
        {:error, :invalid_transition}

      {:error, reason} = error ->
        Logger.error("Task execution failed for #{task.id}: #{inspect(reason)}")
        Tasks.update_task_status(task, "failed", %{error: inspect(reason)})
        error
    end
  end

  defp analyze_and_decide(task, conversation) do
    system_prompt = build_system_prompt(task)

    messages =
      [
        %{role: "system", content: system_prompt},
        %{role: "user", content: build_task_context(task)}
      ] ++ conversation

    case LLMClient.chat_completion(messages, tools: available_tools()) do
      {:ok, %{content: content, tool_calls: tool_calls}} ->
        parse_agent_decision(%{"content" => content, "tool_calls" => tool_calls})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_system_prompt(task) do
    """
    You are an AI agent helping to complete a task of type: #{task.task_type}.

    Your responsibilities:
    1. Analyze the task requirements and conversation history
    2. Determine if you need to use a tool or request user input
    3. If using a tool, provide the tool name and arguments
    4. If requesting input, provide a clear question to the user
    5. If the task is complete, summarize the result

    Available actions:
    - use_tool: Call a tool to perform an action
    - request_input: Ask the user for information
    - complete: Mark the task as done with a result

    Task context:
    Title: #{task.title}
    Description: #{task.description || "No description"}
    Current context: #{inspect(task.context)}
    """
  end

  defp build_task_context(_task) do
    """
    Please analyze this task and decide on the next action.

    Respond with one of:
    1. {"action": "use_tool", "tool": "tool_name", "arguments": {...}}
    2. {"action": "request_input", "question": "What information do you need?"}
    3. {"action": "complete", "result": {...}}
    """
  end

  defp available_tools do
    [
      %{
        type: "function",
        function: %{
          name: "send_email",
          description: "Send an email message",
          parameters: %{
            type: "object",
            properties: %{
              to: %{type: "string", description: "Recipient email address"},
              subject: %{type: "string", description: "Email subject"},
              body: %{type: "string", description: "Email body content"}
            },
            required: ["to", "subject", "body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "search_knowledge",
          description: "Search the user's knowledge base for relevant information",
          parameters: %{
            type: "object",
            properties: %{
              query: %{type: "string", description: "Search query"}
            },
            required: ["query"]
          }
        }
      }
    ]
  end

  defp parse_agent_decision(%{"content" => _content, "tool_calls" => tool_calls})
       when is_list(tool_calls) and length(tool_calls) > 0 do
    [tool_call | _] = tool_calls

    decision = %{
      action: "use_tool",
      tool: tool_call["function"]["name"],
      arguments: Jason.decode!(tool_call["function"]["arguments"])
    }

    {:ok, decision}
  end

  defp parse_agent_decision(%{"content" => content}) do
    case Jason.decode(content) do
      {:ok, %{"action" => action} = decision}
      when action in ["use_tool", "request_input", "complete"] ->
        {:ok, decision}

      {:ok, _} ->
        {:error, :invalid_decision_format}

      {:error, _} ->
        # If not JSON, treat as a message requiring input
        {:ok, %{"action" => "request_input", "question" => content}}
    end
  end

  defp execute_decision(task, %{"action" => "use_tool", "tool" => tool_name, "arguments" => args}) do
    Logger.info("Task #{task.id}: Executing tool #{tool_name}")

    case ToolExecutor.execute(tool_name, args, %{user_id: task.user_id}) do
      {:ok, result} ->
        Tasks.add_task_message(task.id, %{
          role: "tool",
          content: "Tool #{tool_name} executed successfully",
          metadata: %{"tool" => tool_name, "result" => result}
        })

        {:ok, %{type: "tool_result", tool: tool_name, result: result}}

      {:error, reason} ->
        {:error, {:tool_execution_failed, tool_name, reason}}
    end
  end

  defp execute_decision(task, %{"action" => "request_input", "question" => question}) do
    Logger.info("Task #{task.id}: Requesting user input")
    {:ok, %{type: "request_input", message: question}}
  end

  defp execute_decision(_task, %{"action" => "complete", "result" => result}) do
    {:ok, %{type: "complete", result: result}}
  end

  defp execute_decision(_task, _decision) do
    {:error, :unknown_action}
  end

  defp handle_execution_result(task, %{type: "complete", result: result}) do
    Tasks.update_task_status(task, "completed", %{result: result})

    Tasks.add_task_message(task.id, %{
      role: "agent",
      content: "Task completed successfully",
      metadata: %{"result" => result}
    })

    {:ok, :completed, result}
  end

  defp handle_execution_result(task, %{type: "request_input", message: message}) do
    Tasks.update_task_status(task, "waiting_for_input")

    Tasks.add_task_message(task.id, %{
      role: "agent",
      content: message
    })

    {:ok, :waiting_for_input, message}
  end

  defp handle_execution_result(task, %{type: "tool_result"}) do
    # Tool executed successfully, continue with next step
    Tasks.add_task_message(task.id, %{
      role: "system",
      content: "Tool executed, determining next action..."
    })

    {:ok, :continue}
  end

  @doc """
  Handles user input for a task that's waiting for input.
  """
  @spec handle_user_input(Task.t(), String.t()) :: {:ok, :continue} | {:error, term()}
  def handle_user_input(task, user_input) do
    if task.status == "waiting_for_input" do
      Tasks.add_task_message(task.id, %{
        role: "user",
        content: user_input
      })

      Tasks.update_task_status(task, "in_progress")
      {:ok, :continue}
    else
      {:error, :not_waiting_for_input}
    end
  end
end
