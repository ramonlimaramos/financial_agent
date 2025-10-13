defmodule FinancialAgent.Workers.TaskExecutorWorker do
  @moduledoc """
  Oban worker that executes stateful tasks step by step.

  This worker:
  1. Loads the task
  2. Executes one step via Tasks.Agent
  3. Re-enqueues itself if the task needs to continue
  4. Handles task completion or failure
  """

  use Oban.Worker,
    queue: :tasks,
    max_attempts: 3,
    priority: 1

  require Logger

  alias FinancialAgent.Tasks
  alias FinancialAgent.Tasks.Agent

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    Logger.info("Executing task step: #{task_id}")

    with {:ok, task} <- get_task(task_id),
         result <- Agent.execute_step(task) do
      handle_agent_result(task_id, result)
    else
      {:error, :task_not_found} ->
        Logger.warning("Task #{task_id} not found, skipping")
        :ok

      {:error, reason} ->
        Logger.error("Task execution failed for #{task_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_task(task_id) do
    case Tasks.get_task_with_messages(task_id) do
      nil -> {:error, :task_not_found}
      task -> {:ok, task}
    end
  end

  defp handle_agent_result(task_id, {:ok, :completed, result}) do
    Logger.info("Task #{task_id} completed: #{inspect(result)}")
    :ok
  end

  defp handle_agent_result(task_id, {:ok, :waiting_for_input, message}) do
    Logger.info("Task #{task_id} waiting for input: #{message}")
    :ok
  end

  defp handle_agent_result(task_id, {:ok, :continue}) do
    Logger.info("Task #{task_id} continuing, re-enqueueing...")

    # Re-enqueue the task to continue processing
    %{"task_id" => task_id}
    |> __MODULE__.new(schedule_in: 1)
    |> Oban.insert()

    :ok
  end

  defp handle_agent_result(task_id, {:error, reason}) do
    Logger.error("Task #{task_id} execution error: #{inspect(reason)}")
    {:error, reason}
  end

  @doc """
  Enqueues a task for execution.

  ## Examples

      iex> TaskExecutorWorker.enqueue_task(task_id)
      {:ok, %Oban.Job{}}
  """
  @spec enqueue_task(Ecto.UUID.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue_task(task_id) do
    %{"task_id" => task_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a task for execution after user provides input.

  ## Examples

      iex> TaskExecutorWorker.continue_after_input(task_id, "Tomorrow at 2pm")
      {:ok, %Oban.Job{}}
  """
  @spec continue_after_input(Ecto.UUID.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def continue_after_input(task_id, user_input) do
    with {:ok, task} <- Tasks.get_task(task_id) |> ok_or_error(),
         {:ok, :continue} <- Agent.handle_user_input(task, user_input) do
      enqueue_task(task_id)
    end
  end

  defp ok_or_error(nil), do: {:error, :task_not_found}
  defp ok_or_error(task), do: {:ok, task}
end
