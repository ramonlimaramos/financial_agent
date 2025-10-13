defmodule FinancialAgentWeb.TasksLive.Index do
  use FinancialAgentWeb, :live_view

  alias FinancialAgent.Tasks

  @impl true
  def mount(_params, session, socket) do
    user_id = get_user_id(session)

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:page_title, "Tasks")
     |> assign(:filter, "all")
     |> load_tasks()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = Map.get(params, "filter", "all")

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> load_tasks()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, push_patch(socket, to: ~p"/tasks?#{[filter: filter]}")}
  end

  @impl true
  def handle_event("cancel", %{"id" => id}, socket) do
    task = Tasks.get_task(id)

    if task do
      case Tasks.cancel_task(task) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Task cancelled successfully")
           |> load_tasks()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to cancel task")}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_tasks(socket) do
    user_id = socket.assigns.user_id
    filter = socket.assigns.filter

    tasks =
      case filter do
        "active" ->
          Tasks.list_user_tasks_by_status(user_id, "in_progress") ++
            Tasks.list_user_tasks_by_status(user_id, "pending") ++
            Tasks.list_user_tasks_by_status(user_id, "waiting_for_input")

        "completed" ->
          Tasks.list_user_tasks_by_status(user_id, "completed")

        "failed" ->
          Tasks.list_user_tasks_by_status(user_id, "failed")

        _ ->
          Tasks.list_user_tasks(user_id)
      end

    assign(socket, :tasks, tasks)
  end

  defp get_user_id(session) do
    # TODO: Get from session after auth is implemented
    case Map.get(session, "user_id") do
      nil ->
        # Fallback for development
        case FinancialAgent.Repo.all(FinancialAgent.Accounts.User) do
          [user | _] -> user.id
          [] -> raise "No users found. Please create a user first."
        end

      user_id ->
        user_id
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-4xl">
        <.header>
          Tasks
          <:subtitle>View and manage your AI-powered tasks</:subtitle>
        </.header>

        <div class="mt-6 flex space-x-4 border-b border-gray-200">
          <button
            phx-click="filter"
            phx-value-filter="all"
            class={[
              "px-3 py-2 text-sm font-medium border-b-2 -mb-px",
              if(@filter == "all",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700"
              )
            ]}
          >
            All
          </button>
          <button
            phx-click="filter"
            phx-value-filter="active"
            class={[
              "px-3 py-2 text-sm font-medium border-b-2 -mb-px",
              if(@filter == "active",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700"
              )
            ]}
          >
            Active
          </button>
          <button
            phx-click="filter"
            phx-value-filter="completed"
            class={[
              "px-3 py-2 text-sm font-medium border-b-2 -mb-px",
              if(@filter == "completed",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700"
              )
            ]}
          >
            Completed
          </button>
          <button
            phx-click="filter"
            phx-value-filter="failed"
            class={[
              "px-3 py-2 text-sm font-medium border-b-2 -mb-px",
              if(@filter == "failed",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700"
              )
            ]}
          >
            Failed
          </button>
        </div>

        <div class="mt-6 space-y-4">
          <div :for={task <- @tasks} class="bg-white shadow rounded-lg p-6">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex items-center space-x-3">
                  <h3 class="text-lg font-medium text-gray-900">{task.title}</h3>
                  <.status_badge status={task.status} />
                </div>

                <p :if={task.description} class="mt-2 text-sm text-gray-600">
                  {task.description}
                </p>

                <div class="mt-3 flex items-center space-x-4 text-sm text-gray-500">
                  <span>
                    Type: {task.task_type |> String.replace("_", " ") |> String.capitalize()}
                  </span>
                  <span>•</span>
                  <span>Created {format_datetime(task.inserted_at)}</span>
                  <span :if={task.completed_at}>
                    •
                  </span>
                  <span :if={task.completed_at}>
                    Completed {format_datetime(task.completed_at)}
                  </span>
                </div>
              </div>

              <div class="ml-4 flex flex-col space-y-2">
                <.link
                  navigate={~p"/tasks/#{task.id}"}
                  class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  View Details
                </.link>

                <button
                  :if={task.status in ["pending", "in_progress", "waiting_for_input"]}
                  phx-click="cancel"
                  phx-value-id={task.id}
                  data-confirm="Are you sure you want to cancel this task?"
                  class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-red-600 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-red-50"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>

        <div :if={Enum.empty?(@tasks)} class="text-center mt-8">
          <svg
            class="mx-auto h-12 w-12 text-gray-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"
            />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No tasks</h3>
          <p class="mt-1 text-sm text-gray-500">
            <%= case @filter do %>
              <% "active" -> %>
                You don't have any active tasks at the moment.
              <% "completed" -> %>
                You don't have any completed tasks yet.
              <% "failed" -> %>
                You don't have any failed tasks.
              <% _ -> %>
                Tasks will appear here when you create instructions that trigger them.
            <% end %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      status_color(@status)
    ]}>
      {@status |> String.replace("_", " ") |> String.capitalize()}
    </span>
    """
  end

  defp status_color("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("in_progress"), do: "bg-blue-100 text-blue-800"
  defp status_color("waiting_for_input"), do: "bg-purple-100 text-purple-800"
  defp status_color("completed"), do: "bg-green-100 text-green-800"
  defp status_color("failed"), do: "bg-red-100 text-red-800"
  defp status_color("cancelled"), do: "bg-gray-100 text-gray-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end
