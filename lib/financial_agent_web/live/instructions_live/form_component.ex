defmodule FinancialAgentWeb.InstructionsLive.FormComponent do
  use FinancialAgentWeb, :live_component

  alias FinancialAgent.Instructions

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure when and how this instruction should run</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="instruction-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:trigger_type]}
          type="select"
          label="Trigger type"
          prompt="Choose a trigger"
          options={[
            {"New Email", "new_email"},
            {"New Contact", "new_contact"},
            {"Scheduled", "scheduled"}
          ]}
        />

        <.input
          field={@form[:condition_text]}
          type="textarea"
          label="Condition"
          placeholder="Describe when this instruction should trigger (e.g., 'Email mentions pricing')"
          rows="3"
        />

        <.input
          field={@form[:action_text]}
          type="textarea"
          label="Action"
          placeholder="Describe what should happen (e.g., 'Send them our pricing document link')"
          rows="3"
        />

        <.input field={@form[:is_active]} type="checkbox" label="Active" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Instruction</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{instruction: instruction} = assigns, socket) do
    changeset = Instructions.change_instruction(instruction)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"instruction" => instruction_params}, socket) do
    changeset =
      socket.assigns.instruction
      |> Instructions.change_instruction(instruction_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"instruction" => instruction_params}, socket) do
    save_instruction(socket, socket.assigns.action, instruction_params)
  end

  defp save_instruction(socket, :edit, instruction_params) do
    case Instructions.update_instruction(socket.assigns.instruction, instruction_params) do
      {:ok, instruction} ->
        notify_parent({:saved, instruction})

        {:noreply,
         socket
         |> put_flash(:info, "Instruction updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_instruction(socket, :new, instruction_params) do
    instruction_params = Map.put(instruction_params, "user_id", socket.assigns.user_id)

    case Instructions.create_instruction(instruction_params) do
      {:ok, instruction} ->
        notify_parent({:saved, instruction})

        {:noreply,
         socket
         |> put_flash(:info, "Instruction created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
