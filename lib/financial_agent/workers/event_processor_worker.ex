defmodule FinancialAgent.Workers.EventProcessorWorker do
  @moduledoc """
  Oban worker that processes incoming events and matches them against user instructions.

  When an event (like a new email) comes in, this worker:
  1. Loads the user's active instructions for that event type
  2. Uses the Matcher to find matching instructions
  3. Uses the Executor to perform the instruction's action
  """

  use Oban.Worker,
    queue: :events,
    max_attempts: 3,
    priority: 1

  alias FinancialAgent.Instructions
  alias FinancialAgent.Instructions.{Matcher, Executor}

  require Logger

  @type event_args :: %{
          user_id: String.t(),
          event_type: String.t(),
          event_data: map()
        }

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    user_id = Map.fetch!(args, "user_id")
    event_type = Map.fetch!(args, "event_type")
    event_data = Map.fetch!(args, "event_data")

    Logger.info("Processing event type=#{event_type} for user=#{user_id}")

    with {:ok, instructions} <- load_active_instructions(user_id, event_type),
         {:ok, match_result} <- match_instructions(event_data, instructions),
         :ok <- execute_if_matched(match_result, user_id, event_data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Event processing failed: #{inspect(reason)}")
        error
    end
  end

  defp load_active_instructions(user_id, event_type) do
    # Map event types to instruction trigger types
    trigger_type =
      case event_type do
        "email" -> "new_email"
        "contact" -> "new_contact"
        _ -> event_type
      end

    instructions = Instructions.list_active_instructions(user_id, trigger_type)
    {:ok, instructions}
  rescue
    error ->
      {:error, {:database_error, error}}
  end

  defp match_instructions(_event_data, []) do
    Logger.debug("No active instructions found for this event")
    {:ok, %{matched: false, instruction: nil, confidence: 0.0}}
  end

  defp match_instructions(event_data, instructions) do
    # Convert string keys to atom keys for matcher
    normalized_event = %{
      type: Map.get(event_data, "type", "email"),
      subject: Map.get(event_data, "subject"),
      from: Map.get(event_data, "from"),
      content: Map.get(event_data, "content", ""),
      metadata: Map.get(event_data, "metadata", %{})
    }

    Matcher.match_event(normalized_event, instructions)
  end

  defp execute_if_matched(%{matched: false}, _user_id, _event_data) do
    Logger.debug("No instruction matched this event")
    :ok
  end

  defp execute_if_matched(%{matched: true, instruction: instruction}, user_id, event_data) do
    Logger.info(
      "Instruction #{instruction.id} matched! Executing action: #{String.slice(instruction.action_text, 0, 100)}"
    )

    normalized_event = %{
      type: Map.get(event_data, "type", "email"),
      subject: Map.get(event_data, "subject"),
      from: Map.get(event_data, "from"),
      content: Map.get(event_data, "content", ""),
      metadata: Map.get(event_data, "metadata", %{})
    }

    context = %{
      user_id: user_id,
      event_data: normalized_event
    }

    case Executor.execute(instruction, context) do
      {:ok, %{success: true}} ->
        Logger.info("Instruction executed successfully")
        :ok

      {:ok, %{success: false, error: error}} ->
        Logger.error("Instruction execution failed: #{error}")
        {:error, :execution_failed}

      {:error, reason} ->
        Logger.error("Instruction execution error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
