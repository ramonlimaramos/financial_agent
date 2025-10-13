defmodule FinancialAgent.Tasks.StateMachine do
  @moduledoc """
  State machine for managing task status transitions.

  Valid transitions:
  - pending -> in_progress
  - pending -> cancelled
  - in_progress -> waiting_for_input
  - in_progress -> completed
  - in_progress -> failed
  - in_progress -> cancelled
  - waiting_for_input -> in_progress
  - waiting_for_input -> cancelled
  """

  alias FinancialAgent.Tasks.Task

  @valid_transitions %{
    "pending" => ["in_progress", "cancelled"],
    "in_progress" => ["waiting_for_input", "completed", "failed", "cancelled"],
    "waiting_for_input" => ["in_progress", "cancelled"],
    "completed" => [],
    "failed" => [],
    "cancelled" => []
  }

  @doc """
  Checks if a transition from one status to another is valid.

  ## Examples

      iex> StateMachine.can_transition?("pending", "in_progress")
      true

      iex> StateMachine.can_transition?("completed", "pending")
      false
  """
  @spec can_transition?(String.t(), String.t()) :: boolean()
  def can_transition?(from_status, to_status) do
    case Map.get(@valid_transitions, from_status) do
      nil -> false
      allowed_statuses -> to_status in allowed_statuses
    end
  end

  @doc """
  Validates a transition and returns :ok or {:error, reason}.

  ## Examples

      iex> StateMachine.validate_transition(%Task{status: "pending"}, "in_progress")
      :ok

      iex> StateMachine.validate_transition(%Task{status: "completed"}, "pending")
      {:error, :invalid_transition}
  """
  @spec validate_transition(Task.t(), String.t()) :: :ok | {:error, :invalid_transition}
  def validate_transition(%Task{status: current_status}, new_status) do
    if can_transition?(current_status, new_status) do
      :ok
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Returns list of valid next statuses for a given current status.

  ## Examples

      iex> StateMachine.next_statuses("pending")
      ["in_progress", "cancelled"]

      iex> StateMachine.next_statuses("completed")
      []
  """
  @spec next_statuses(String.t()) :: [String.t()]
  def next_statuses(current_status) do
    Map.get(@valid_transitions, current_status, [])
  end

  @doc """
  Checks if a task is in a terminal state (completed, failed, or cancelled).
  """
  @spec terminal_state?(String.t()) :: boolean()
  def terminal_state?(status) when status in ["completed", "failed", "cancelled"], do: true
  def terminal_state?(_status), do: false

  @doc """
  Checks if a task is in an active state (pending, in_progress, or waiting_for_input).
  """
  @spec active_state?(String.t()) :: boolean()
  def active_state?(status) when status in ["pending", "in_progress", "waiting_for_input"],
    do: true

  def active_state?(_status), do: false
end
