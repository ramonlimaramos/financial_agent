defmodule FinancialAgentWeb.TasksLive.Show do
  use FinancialAgentWeb, :live_view

  alias FinancialAgent.Tasks
  alias FinancialAgent.Workers.TaskExecutorWorker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Tasks.get_task_with_messages(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Task not found")
         |> redirect(to: ~p"/tasks")}

      task ->
        {:ok,
         socket
         |> assign(:task, task)
         |> assign(:page_title, task.title)
         |> assign(:user_input, "")}
    end
  end

  @impl true
  def handle_event("submit_input", %{"user_input" => user_input}, socket) do
    task = socket.assigns.task

    if task.status == "waiting_for_input" and String.trim(user_input) != "" do
      case TaskExecutorWorker.continue_after_input(task.id, user_input) do
        {:ok, _job} ->
          # Reload task to show new message
          updated_task = Tasks.get_task_with_messages(task.id)

          {:noreply,
           socket
           |> assign(:task, updated_task)
           |> assign(:user_input, "")
           |> put_flash(:info, "Input submitted, task continuing...")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to submit input")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please enter valid input")}
    end
  end

  @impl true
  def handle_event("retry", _params, socket) do
    task = socket.assigns.task

    if task.status == "failed" do
      # Re-enqueue the task
      case TaskExecutorWorker.enqueue_task(task.id) do
        {:ok, _job} ->
          {:noreply,
           socket
           |> put_flash(:info, "Task retrying...")
           |> push_navigate(to: ~p"/tasks")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to retry task")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-4xl">
        <div class="mb-4">
          <.link
            navigate={~p"/tasks"}
            class="inline-flex items-center text-sm font-medium text-gray-500 hover:text-gray-700"
          >
            <svg
              class="mr-2 h-4 w-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              aria-hidden="true"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10 19l-7-7m0 0l7-7m-7 7h18"
              />
            </svg>
            Back to Tasks
          </.link>
        </div>

        <.header>
          {@task.title}
          <:subtitle>
            <div class="flex items-center space-x-3">
              <.status_badge status={@task.status} />
              <span class="text-sm text-gray-500">
                Created {format_datetime(@task.inserted_at)}
              </span>
            </div>
          </:subtitle>
        </.header>

        <div class="mt-6 bg-white shadow rounded-lg divide-y divide-gray-200">
          <div class="px-6 py-4">
            <h3 class="text-sm font-medium text-gray-900">Task Details</h3>
            <dl class="mt-4 space-y-3">
              <div>
                <dt class="text-sm font-medium text-gray-500">Type</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  {@task.task_type |> String.replace("_", " ") |> String.capitalize()}
                </dd>
              </div>
              <div :if={@task.description}>
                <dt class="text-sm font-medium text-gray-500">Description</dt>
                <dd class="mt-1 text-sm text-gray-900">{@task.description}</dd>
              </div>
              <div :if={@task.completed_at}>
                <dt class="text-sm font-medium text-gray-500">Completed At</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  {format_datetime(@task.completed_at)}
                </dd>
              </div>
              <div :if={@task.result}>
                <dt class="text-sm font-medium text-gray-500">Result</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <pre class="bg-gray-50 p-3 rounded text-xs overflow-x-auto"><%= Jason.encode!(@task.result, pretty: true) %></pre>
                </dd>
              </div>
              <div :if={@task.error}>
                <dt class="text-sm font-medium text-gray-500">Error</dt>
                <dd class="mt-1 text-sm text-red-600">{@task.error}</dd>
              </div>
            </dl>
          </div>

          <div class="px-6 py-4">
            <h3 class="text-sm font-medium text-gray-900 mb-4">Conversation History</h3>

            <div :if={Enum.empty?(@task.messages)} class="text-sm text-gray-500">
              No conversation history yet.
            </div>

            <div class="space-y-4">
              <div
                :for={message <- @task.messages}
                class={[
                  "p-4 rounded-lg",
                  message_background(message.role)
                ]}
              >
                <div class="flex items-start justify-between">
                  <div class="flex-1">
                    <div class="flex items-center space-x-2">
                      <span class="text-xs font-medium text-gray-500 uppercase">
                        {message.role}
                      </span>
                      <span class="text-xs text-gray-400">
                        {format_datetime(message.inserted_at)}
                      </span>
                    </div>
                    <p class="mt-2 text-sm text-gray-900 whitespace-pre-wrap">{message.content}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div :if={@task.status == "waiting_for_input"} class="px-6 py-4 bg-blue-50">
            <h3 class="text-sm font-medium text-gray-900 mb-4">Task is waiting for your input</h3>

            <form phx-submit="submit_input" class="space-y-4">
              <div>
                <textarea
                  name="user_input"
                  rows="3"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                  placeholder="Type your response here..."
                  value={@user_input}
                ><%= @user_input %></textarea>
              </div>
              <div class="flex justify-end">
                <button
                  type="submit"
                  class="inline-flex items-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
                >
                  Submit
                </button>
              </div>
            </form>
          </div>

          <div :if={@task.status == "failed"} class="px-6 py-4 bg-red-50">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-sm font-medium text-red-800">Task Failed</h3>
                <p class="mt-1 text-sm text-red-700">
                  This task encountered an error and could not be completed.
                </p>
              </div>
              <button
                phx-click="retry"
                class="inline-flex items-center rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500"
              >
                Retry
              </button>
            </div>
          </div>
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

  defp message_background("user"), do: "bg-blue-50"
  defp message_background("agent"), do: "bg-gray-50"
  defp message_background("system"), do: "bg-yellow-50"
  defp message_background("tool"), do: "bg-green-50"
  defp message_background(_), do: "bg-gray-50"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end
