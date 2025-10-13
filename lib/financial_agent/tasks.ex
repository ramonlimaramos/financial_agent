defmodule FinancialAgent.Tasks do
  @moduledoc """
  Context module for managing stateful tasks and their conversation history.

  Tasks represent complex, multi-turn operations that may require:
  - Multiple steps with state transitions
  - User input or confirmation
  - External API calls
  - Tool execution

  Each task maintains a conversation history via TaskMessage records.
  """

  import Ecto.Query, warn: false

  alias FinancialAgent.Repo
  alias FinancialAgent.Tasks.{Task, TaskMessage}

  ## Task CRUD operations

  @doc """
  Creates a new task.

  ## Examples

      iex> create_task(%{user_id: user_id, title: "Schedule meeting", task_type: "schedule_meeting"})
      {:ok, %Task{}}

      iex> create_task(%{title: "Invalid"})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_task(map()) :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single task by ID.

  Returns `nil` if the task does not exist.
  """
  @spec get_task(Ecto.UUID.t()) :: Task.t() | nil
  def get_task(id) do
    Repo.get(Task, id)
  end

  @doc """
  Gets a single task by ID, preloading associations.
  """
  @spec get_task_with_messages(Ecto.UUID.t()) :: Task.t() | nil
  def get_task_with_messages(id) do
    Task
    |> where([t], t.id == ^id)
    |> preload(:messages)
    |> Repo.one()
  end

  @doc """
  Updates a task's status and optionally other fields.

  ## Examples

      iex> update_task_status(task, "in_progress")
      {:ok, %Task{}}

      iex> update_task_status(task, "completed", %{result: %{success: true}})
      {:ok, %Task{}}
  """
  @spec update_task_status(Task.t(), String.t(), map()) ::
          {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def update_task_status(task, new_status, attrs \\ %{}) do
    task
    |> Task.status_changeset(new_status, attrs)
    |> Repo.update()
  end

  @doc """
  Lists all tasks for a user, ordered by most recent first.
  """
  @spec list_user_tasks(Ecto.UUID.t()) :: [Task.t()]
  def list_user_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists tasks for a user filtered by status.
  """
  @spec list_user_tasks_by_status(Ecto.UUID.t(), String.t()) :: [Task.t()]
  def list_user_tasks_by_status(user_id, status) do
    Task
    |> where([t], t.user_id == ^user_id and t.status == ^status)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists tasks for a user filtered by task type.
  """
  @spec list_user_tasks_by_type(Ecto.UUID.t(), String.t()) :: [Task.t()]
  def list_user_tasks_by_type(user_id, task_type) do
    Task
    |> where([t], t.user_id == ^user_id and t.task_type == ^task_type)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Cancels a task by setting its status to "cancelled".
  """
  @spec cancel_task(Task.t()) :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def cancel_task(task) do
    update_task_status(task, "cancelled")
  end

  @doc """
  Deletes a task and all its messages.
  """
  @spec delete_task(Task.t()) :: {:ok, Task.t()} | {:error, Ecto.Changeset.t()}
  def delete_task(task) do
    Repo.delete(task)
  end

  ## TaskMessage operations

  @doc """
  Adds a message to a task's conversation history.

  ## Examples

      iex> add_task_message(task.id, %{role: "user", content: "Schedule for tomorrow at 2pm"})
      {:ok, %TaskMessage{}}
  """
  @spec add_task_message(Ecto.UUID.t(), map()) ::
          {:ok, TaskMessage.t()} | {:error, Ecto.Changeset.t()}
  def add_task_message(task_id, attrs) do
    attrs
    |> Map.put(:task_id, task_id)
    |> then(&TaskMessage.changeset(%TaskMessage{}, &1))
    |> Repo.insert()
  end

  @doc """
  Lists all messages for a task, ordered chronologically.
  """
  @spec list_task_messages(Ecto.UUID.t()) :: [TaskMessage.t()]
  def list_task_messages(task_id) do
    TaskMessage
    |> where([m], m.task_id == ^task_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the conversation history for a task formatted for LLM context.

  Returns a list of message maps with :role and :content keys.
  """
  @spec get_task_conversation(Ecto.UUID.t()) :: [%{role: String.t(), content: String.t()}]
  def get_task_conversation(task_id) do
    task_id
    |> list_task_messages()
    |> Enum.map(fn message ->
      %{role: message.role, content: message.content}
    end)
  end

  @doc """
  Counts tasks by status for a user.
  """
  @spec count_tasks_by_status(Ecto.UUID.t(), String.t()) :: non_neg_integer()
  def count_tasks_by_status(user_id, status) do
    Task
    |> where([t], t.user_id == ^user_id and t.status == ^status)
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if a user has any active tasks (pending or in_progress).
  """
  @spec has_active_tasks?(Ecto.UUID.t()) :: boolean()
  def has_active_tasks?(user_id) do
    Task
    |> where([t], t.user_id == ^user_id)
    |> where([t], t.status in ["pending", "in_progress", "waiting_for_input"])
    |> Repo.exists?()
  end
end
