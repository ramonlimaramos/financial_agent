defmodule FinancialAgentWeb.InstructionsLive.Index do
  use FinancialAgentWeb, :live_view

  alias FinancialAgent.Instructions
  alias FinancialAgent.Instructions.Instruction

  @impl true
  def mount(_params, session, socket) do
    user_id = get_user_id(session)

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:page_title, "Instructions")
     |> stream(:instructions, Instructions.list_instructions(user_id))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Instruction")
    |> assign(:instruction, Instructions.get_instruction!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Instruction")
    |> assign(:instruction, %Instruction{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Instructions")
    |> assign(:instruction, nil)
  end

  @impl true
  def handle_info(
        {FinancialAgentWeb.InstructionsLive.FormComponent, {:saved, instruction}},
        socket
      ) do
    {:noreply, stream_insert(socket, :instructions, instruction)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    instruction = Instructions.get_instruction!(id)
    {:ok, _} = Instructions.delete_instruction(instruction)

    {:noreply, stream_delete(socket, :instructions, instruction)}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    instruction = Instructions.get_instruction!(id)
    {:ok, updated_instruction} = Instructions.toggle_instruction(instruction)

    {:noreply, stream_insert(socket, :instructions, updated_instruction)}
  end

  defp get_user_id(session) do
    # TODO: Get from session after auth is implemented
    # For now, get first user from DB for testing
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
          Instructions
          <:subtitle>Automate your workflows with AI-powered instructions</:subtitle>
          <:actions>
            <.link patch={~p"/instructions/new"}>
              <.button>New Instruction</.button>
            </.link>
          </:actions>
        </.header>

        <div class="mt-8 space-y-4" id="instructions" phx-update="stream">
          <div
            :for={{dom_id, instruction} <- @streams.instructions}
            id={dom_id}
            class="bg-white shadow rounded-lg p-6"
          >
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex items-center space-x-3">
                  <h3 class="text-lg font-medium text-gray-900">
                    {instruction.trigger_type |> String.replace("_", " ") |> String.capitalize()}
                  </h3>
                  <span class={[
                    "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
                    if(instruction.is_active,
                      do: "bg-green-100 text-green-800",
                      else: "bg-gray-100 text-gray-800"
                    )
                  ]}>
                    {if instruction.is_active, do: "Active", else: "Inactive"}
                  </span>
                </div>

                <div class="mt-4 space-y-2">
                  <div>
                    <p class="text-sm font-medium text-gray-500">When:</p>
                    <p class="mt-1 text-sm text-gray-900">{instruction.condition_text}</p>
                  </div>
                  <div>
                    <p class="text-sm font-medium text-gray-500">Then:</p>
                    <p class="mt-1 text-sm text-gray-900">{instruction.action_text}</p>
                  </div>
                </div>
              </div>

              <div class="ml-4 flex flex-col space-y-2">
                <button
                  phx-click="toggle"
                  phx-value-id={instruction.id}
                  class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  {if instruction.is_active, do: "Deactivate", else: "Activate"}
                </button>

                <.link
                  patch={~p"/instructions/#{instruction}/edit"}
                  class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  Edit
                </.link>

                <.link
                  phx-click={JS.push("delete", value: %{id: instruction.id}) |> hide("##{dom_id}")}
                  data-confirm="Are you sure you want to delete this instruction?"
                  class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-red-600 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-red-50"
                >
                  Delete
                </.link>
              </div>
            </div>
          </div>
        </div>

        <div :if={Enum.empty?(@streams.instructions)} class="text-center mt-8">
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
              d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
            />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No instructions</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new instruction.</p>
          <div class="mt-6">
            <.link patch={~p"/instructions/new"}>
              <.button>New Instruction</.button>
            </.link>
          </div>
        </div>
      </div>
    </div>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="instruction-modal"
      show
      on_cancel={JS.patch(~p"/instructions")}
    >
      <.live_component
        module={FinancialAgentWeb.InstructionsLive.FormComponent}
        id={@instruction.id || :new}
        title={@page_title}
        action={@live_action}
        instruction={@instruction}
        user_id={@user_id}
        patch={~p"/instructions"}
      />
    </.modal>
    """
  end
end
