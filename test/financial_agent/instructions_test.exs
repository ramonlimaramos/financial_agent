defmodule FinancialAgent.InstructionsTest do
  use FinancialAgent.DataCase, async: true

  import FinancialAgent.Factory

  alias FinancialAgent.Instructions
  alias FinancialAgent.Instructions.Instruction

  describe "create_instruction/1" do
    test "creates instruction with valid params" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        trigger_type: "new_email",
        condition_text: "Email mentions pricing",
        action_text: "Send pricing document"
      }

      assert {:ok, %Instruction{} = instruction} = Instructions.create_instruction(attrs)
      assert instruction.user_id == user.id
      assert instruction.trigger_type == "new_email"
      assert instruction.condition_text == "Email mentions pricing"
      assert instruction.action_text == "Send pricing document"
      assert instruction.is_active == true
    end

    test "returns error with invalid trigger_type" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        trigger_type: "invalid_type",
        condition_text: "Some condition",
        action_text: "Some action"
      }

      assert {:error, changeset} = Instructions.create_instruction(attrs)
      assert "is invalid" in errors_on(changeset).trigger_type
    end

    test "returns error when required fields are missing" do
      attrs = %{}

      assert {:error, changeset} = Instructions.create_instruction(attrs)

      assert %{user_id: _, trigger_type: _, condition_text: _, action_text: _} =
               errors_on(changeset)
    end

    test "returns error when condition_text is too short" do
      user = insert(:user)

      attrs = %{
        user_id: user.id,
        trigger_type: "new_email",
        condition_text: "abc",
        action_text: "Some action text"
      }

      assert {:error, changeset} = Instructions.create_instruction(attrs)
      assert "should be at least 5 character(s)" in errors_on(changeset).condition_text
    end
  end

  describe "update_instruction/2" do
    test "updates instruction with valid params" do
      instruction = insert(:instruction)

      attrs = %{
        condition_text: "Updated condition text",
        action_text: "Updated action text"
      }

      assert {:ok, updated} = Instructions.update_instruction(instruction, attrs)
      assert updated.condition_text == "Updated condition text"
      assert updated.action_text == "Updated action text"
      assert updated.id == instruction.id
    end

    test "returns error with invalid data" do
      instruction = insert(:instruction)

      attrs = %{trigger_type: "invalid_type"}

      assert {:error, changeset} = Instructions.update_instruction(instruction, attrs)
      assert "is invalid" in errors_on(changeset).trigger_type
    end
  end

  describe "delete_instruction/1" do
    test "deletes instruction" do
      instruction = insert(:instruction)

      assert {:ok, deleted} = Instructions.delete_instruction(instruction)
      assert deleted.id == instruction.id
      assert {:error, :not_found} = Instructions.get_instruction(instruction.id)
    end
  end

  describe "get_instruction/1" do
    test "returns instruction when found" do
      instruction = insert(:instruction)

      assert {:ok, found} = Instructions.get_instruction(instruction.id)
      assert found.id == instruction.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Instructions.get_instruction(Ecto.UUID.generate())
    end
  end

  describe "get_instruction!/1" do
    test "returns instruction when found" do
      instruction = insert(:instruction)

      found = Instructions.get_instruction!(instruction.id)
      assert found.id == instruction.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Instructions.get_instruction!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_instructions/1" do
    test "lists all instructions for a user" do
      user = insert(:user)
      instruction1 = insert(:instruction, user: user)
      instruction2 = insert(:instruction, user: user)
      _other_user_instruction = insert(:instruction)

      instructions = Instructions.list_instructions(user.id)

      assert length(instructions) == 2
      instruction_ids = Enum.map(instructions, & &1.id)
      assert instruction1.id in instruction_ids
      assert instruction2.id in instruction_ids
    end

    test "returns empty list when user has no instructions" do
      user = insert(:user)

      assert [] = Instructions.list_instructions(user.id)
    end

    test "orders by inserted_at desc" do
      user = insert(:user)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -3600, :second)

      _instruction1 =
        insert(:instruction,
          user: user,
          inserted_at: earlier
        )

      instruction2 =
        insert(:instruction,
          user: user,
          inserted_at: now
        )

      instructions = Instructions.list_instructions(user.id)

      assert List.first(instructions).id == instruction2.id
    end
  end

  describe "list_active_instructions/2" do
    test "lists only active instructions for a user" do
      user = insert(:user)
      active1 = insert(:instruction, user: user, is_active: true)
      active2 = insert(:instruction, user: user, is_active: true)
      _inactive = insert(:instruction, user: user, is_active: false)

      instructions = Instructions.list_active_instructions(user.id)

      assert length(instructions) == 2
      instruction_ids = Enum.map(instructions, & &1.id)
      assert active1.id in instruction_ids
      assert active2.id in instruction_ids
    end

    test "filters by trigger_type when provided" do
      user = insert(:user)
      email_instruction = insert(:instruction, user: user, trigger_type: "new_email")
      _contact_instruction = insert(:instruction, user: user, trigger_type: "new_contact")

      instructions = Instructions.list_active_instructions(user.id, "new_email")

      assert length(instructions) == 1
      assert List.first(instructions).id == email_instruction.id
    end

    test "returns empty list when no active instructions" do
      user = insert(:user)
      _inactive = insert(:instruction, user: user, is_active: false)

      assert [] = Instructions.list_active_instructions(user.id)
    end
  end

  describe "toggle_instruction/1" do
    test "toggles is_active from true to false" do
      instruction = insert(:instruction, is_active: true)

      assert {:ok, toggled} = Instructions.toggle_instruction(instruction)
      assert toggled.is_active == false
      assert toggled.id == instruction.id
    end

    test "toggles is_active from false to true" do
      instruction = insert(:instruction, is_active: false)

      assert {:ok, toggled} = Instructions.toggle_instruction(instruction)
      assert toggled.is_active == true
      assert toggled.id == instruction.id
    end
  end

  describe "has_active_instructions?/2" do
    test "returns true when user has active instructions for trigger type" do
      user = insert(:user)
      insert(:instruction, user: user, trigger_type: "new_email", is_active: true)

      assert Instructions.has_active_instructions?(user.id, "new_email")
    end

    test "returns false when user has no active instructions for trigger type" do
      user = insert(:user)
      insert(:instruction, user: user, trigger_type: "new_email", is_active: false)

      refute Instructions.has_active_instructions?(user.id, "new_email")
    end

    test "returns false when user has active instructions for different trigger type" do
      user = insert(:user)
      insert(:instruction, user: user, trigger_type: "new_contact", is_active: true)

      refute Instructions.has_active_instructions?(user.id, "new_email")
    end

    test "returns false when user has no instructions" do
      user = insert(:user)

      refute Instructions.has_active_instructions?(user.id, "new_email")
    end
  end
end
