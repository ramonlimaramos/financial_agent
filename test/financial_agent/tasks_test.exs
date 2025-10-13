defmodule FinancialAgent.TasksTest do
  use FinancialAgent.DataCase, async: true

  import FinancialAgent.Factory

  alias FinancialAgent.Tasks
  alias FinancialAgent.Tasks.{Task, TaskMessage}

  describe "create_task/1" do
    test "creates a task with valid attributes" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        title: "Schedule meeting",
        description: "Schedule a meeting with the team",
        task_type: "schedule_meeting",
        context: %{"some" => "context"}
      }

      assert {:ok, %Task{} = task} = Tasks.create_task(attrs)
      assert task.title == "Schedule meeting"
      assert task.task_type == "schedule_meeting"
      assert task.status == "pending"
      assert task.context == %{"some" => "context"}
    end

    test "requires user_id" do
      attrs = %{
        title: "Test task",
        task_type: "custom"
      }

      assert {:error, changeset} = Tasks.create_task(attrs)
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires title" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        task_type: "custom"
      }

      assert {:error, changeset} = Tasks.create_task(attrs)
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates task_type is in allowed list" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        title: "Test task",
        task_type: "invalid_type"
      }

      assert {:error, changeset} = Tasks.create_task(attrs)
      assert %{task_type: ["is invalid"]} = errors_on(changeset)
    end

    test "validates title length" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        title: "ab",
        task_type: "custom"
      }

      assert {:error, changeset} = Tasks.create_task(attrs)
      assert %{title: ["should be at least 3 character(s)"]} = errors_on(changeset)
    end
  end

  describe "get_task/1" do
    test "returns task by id" do
      task = insert(:task)

      assert fetched_task = Tasks.get_task(task.id)
      assert fetched_task.id == task.id
      assert fetched_task.title == task.title
    end

    test "returns nil for non-existent id" do
      assert Tasks.get_task(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_task_with_messages/1" do
    test "returns task with preloaded messages" do
      task = insert(:task)
      _message1 = insert(:task_message, task: task, content: "First message")
      _message2 = insert(:task_message, task: task, content: "Second message")

      fetched_task = Tasks.get_task_with_messages(task.id)

      assert fetched_task.id == task.id
      assert length(fetched_task.messages) == 2
    end
  end

  describe "update_task_status/3" do
    test "updates task status" do
      task = insert(:task, status: "pending")

      assert {:ok, updated_task} = Tasks.update_task_status(task, "in_progress")
      assert updated_task.status == "in_progress"
    end

    test "sets completed_at when completing" do
      task = insert(:in_progress_task)

      assert {:ok, updated_task} =
               Tasks.update_task_status(task, "completed", %{result: %{"success" => true}})

      assert updated_task.status == "completed"
      assert updated_task.result == %{"success" => true}
      assert updated_task.completed_at != nil
    end

    test "sets completed_at when failed" do
      task = insert(:in_progress_task)

      assert {:ok, updated_task} =
               Tasks.update_task_status(task, "failed", %{error: "Something went wrong"})

      assert updated_task.status == "failed"
      assert updated_task.completed_at != nil
    end

    test "validates status is in allowed list" do
      task = insert(:task)

      assert {:error, changeset} = Tasks.update_task_status(task, "invalid_status")
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_user_tasks/1" do
    test "returns all tasks for user ordered by most recent" do
      user = insert(:user)
      other_user = insert(:user)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -3600, :second)

      task1 = insert(:task, user: user, inserted_at: earlier)
      task2 = insert(:task, user: user, inserted_at: now)
      _other_task = insert(:task, user: other_user)

      tasks = Tasks.list_user_tasks(user.id)

      assert length(tasks) == 2
      assert hd(tasks).id == task2.id
      assert List.last(tasks).id == task1.id
    end

    test "returns empty list when user has no tasks" do
      user = insert(:user)

      assert Tasks.list_user_tasks(user.id) == []
    end
  end

  describe "list_user_tasks_by_status/2" do
    test "filters tasks by status" do
      user = insert(:user)

      _pending = insert(:task, user: user, status: "pending")
      in_progress = insert(:in_progress_task, user: user)
      _completed = insert(:completed_task, user: user)

      tasks = Tasks.list_user_tasks_by_status(user.id, "in_progress")

      assert length(tasks) == 1
      assert hd(tasks).id == in_progress.id
    end
  end

  describe "list_user_tasks_by_type/2" do
    test "filters tasks by type" do
      user = insert(:user)

      meeting_task = insert(:task, user: user, task_type: "schedule_meeting")
      _email_task = insert(:task, user: user, task_type: "compose_email")

      tasks = Tasks.list_user_tasks_by_type(user.id, "schedule_meeting")

      assert length(tasks) == 1
      assert hd(tasks).id == meeting_task.id
    end
  end

  describe "cancel_task/1" do
    test "sets status to cancelled" do
      task = insert(:task)

      assert {:ok, cancelled_task} = Tasks.cancel_task(task)
      assert cancelled_task.status == "cancelled"
      assert cancelled_task.completed_at != nil
    end
  end

  describe "delete_task/1" do
    test "deletes the task" do
      task = insert(:task)

      assert {:ok, _} = Tasks.delete_task(task)
      assert Tasks.get_task(task.id) == nil
    end
  end

  describe "add_task_message/2" do
    test "adds a message to task" do
      task = insert(:task)

      attrs = %{
        role: "user",
        content: "When can we schedule this?"
      }

      assert {:ok, %TaskMessage{} = message} = Tasks.add_task_message(task.id, attrs)
      assert message.task_id == task.id
      assert message.role == "user"
      assert message.content == "When can we schedule this?"
    end

    test "requires role" do
      task = insert(:task)

      attrs = %{
        content: "Test content"
      }

      assert {:error, changeset} = Tasks.add_task_message(task.id, attrs)
      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates role is in allowed list" do
      task = insert(:task)

      attrs = %{
        role: "invalid_role",
        content: "Test content"
      }

      assert {:error, changeset} = Tasks.add_task_message(task.id, attrs)
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_task_messages/1" do
    test "returns messages ordered chronologically" do
      task = insert(:task)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -3600, :second)

      message1 = insert(:task_message, task: task, content: "First", inserted_at: earlier)
      message2 = insert(:task_message, task: task, content: "Second", inserted_at: now)

      messages = Tasks.list_task_messages(task.id)

      assert length(messages) == 2
      assert hd(messages).id == message1.id
      assert List.last(messages).id == message2.id
    end
  end

  describe "get_task_conversation/1" do
    test "returns formatted conversation history" do
      task = insert(:task)

      insert(:task_message, task: task, role: "user", content: "User message")
      insert(:task_message, task: task, role: "agent", content: "Agent response")

      conversation = Tasks.get_task_conversation(task.id)

      assert length(conversation) == 2
      assert hd(conversation) == %{role: "user", content: "User message"}
      assert List.last(conversation) == %{role: "agent", content: "Agent response"}
    end
  end

  describe "count_tasks_by_status/2" do
    test "counts tasks with given status" do
      user = insert(:user)

      insert(:task, user: user, status: "pending")
      insert(:task, user: user, status: "pending")
      insert(:in_progress_task, user: user)

      assert Tasks.count_tasks_by_status(user.id, "pending") == 2
      assert Tasks.count_tasks_by_status(user.id, "in_progress") == 1
      assert Tasks.count_tasks_by_status(user.id, "completed") == 0
    end
  end

  describe "has_active_tasks?/1" do
    test "returns true when user has active tasks" do
      user = insert(:user)

      insert(:task, user: user, status: "pending")

      assert Tasks.has_active_tasks?(user.id) == true
    end

    test "returns false when user has only completed tasks" do
      user = insert(:user)

      insert(:completed_task, user: user)

      assert Tasks.has_active_tasks?(user.id) == false
    end

    test "returns false when user has no tasks" do
      user = insert(:user)

      assert Tasks.has_active_tasks?(user.id) == false
    end
  end
end
