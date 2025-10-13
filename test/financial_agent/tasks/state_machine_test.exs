defmodule FinancialAgent.Tasks.StateMachineTest do
  use ExUnit.Case, async: true

  import FinancialAgent.Factory

  alias FinancialAgent.Tasks.StateMachine

  describe "can_transition?/2" do
    test "allows pending to in_progress" do
      assert StateMachine.can_transition?("pending", "in_progress") == true
    end

    test "allows pending to cancelled" do
      assert StateMachine.can_transition?("pending", "cancelled") == true
    end

    test "denies pending to completed" do
      assert StateMachine.can_transition?("pending", "completed") == false
    end

    test "allows in_progress to waiting_for_input" do
      assert StateMachine.can_transition?("in_progress", "waiting_for_input") == true
    end

    test "allows in_progress to completed" do
      assert StateMachine.can_transition?("in_progress", "completed") == true
    end

    test "allows in_progress to failed" do
      assert StateMachine.can_transition?("in_progress", "failed") == true
    end

    test "allows in_progress to cancelled" do
      assert StateMachine.can_transition?("in_progress", "cancelled") == true
    end

    test "allows waiting_for_input to in_progress" do
      assert StateMachine.can_transition?("waiting_for_input", "in_progress") == true
    end

    test "allows waiting_for_input to cancelled" do
      assert StateMachine.can_transition?("waiting_for_input", "cancelled") == true
    end

    test "denies completed to any status" do
      assert StateMachine.can_transition?("completed", "in_progress") == false
      assert StateMachine.can_transition?("completed", "pending") == false
    end

    test "denies failed to any status" do
      assert StateMachine.can_transition?("failed", "in_progress") == false
      assert StateMachine.can_transition?("failed", "pending") == false
    end

    test "denies cancelled to any status" do
      assert StateMachine.can_transition?("cancelled", "in_progress") == false
      assert StateMachine.can_transition?("cancelled", "pending") == false
    end
  end

  describe "validate_transition/2" do
    test "returns :ok for valid transition" do
      task = build(:task, status: "pending")

      assert StateMachine.validate_transition(task, "in_progress") == :ok
    end

    test "returns error for invalid transition" do
      task = build(:completed_task)

      assert StateMachine.validate_transition(task, "pending") == {:error, :invalid_transition}
    end
  end

  describe "next_statuses/1" do
    test "returns valid next statuses for pending" do
      assert StateMachine.next_statuses("pending") == ["in_progress", "cancelled"]
    end

    test "returns valid next statuses for in_progress" do
      next = StateMachine.next_statuses("in_progress")

      assert "waiting_for_input" in next
      assert "completed" in next
      assert "failed" in next
      assert "cancelled" in next
    end

    test "returns valid next statuses for waiting_for_input" do
      assert StateMachine.next_statuses("waiting_for_input") == ["in_progress", "cancelled"]
    end

    test "returns empty list for terminal states" do
      assert StateMachine.next_statuses("completed") == []
      assert StateMachine.next_statuses("failed") == []
      assert StateMachine.next_statuses("cancelled") == []
    end
  end

  describe "terminal_state?/1" do
    test "returns true for completed" do
      assert StateMachine.terminal_state?("completed") == true
    end

    test "returns true for failed" do
      assert StateMachine.terminal_state?("failed") == true
    end

    test "returns true for cancelled" do
      assert StateMachine.terminal_state?("cancelled") == true
    end

    test "returns false for active states" do
      assert StateMachine.terminal_state?("pending") == false
      assert StateMachine.terminal_state?("in_progress") == false
      assert StateMachine.terminal_state?("waiting_for_input") == false
    end
  end

  describe "active_state?/1" do
    test "returns true for pending" do
      assert StateMachine.active_state?("pending") == true
    end

    test "returns true for in_progress" do
      assert StateMachine.active_state?("in_progress") == true
    end

    test "returns true for waiting_for_input" do
      assert StateMachine.active_state?("waiting_for_input") == true
    end

    test "returns false for terminal states" do
      assert StateMachine.active_state?("completed") == false
      assert StateMachine.active_state?("failed") == false
      assert StateMachine.active_state?("cancelled") == false
    end
  end
end
