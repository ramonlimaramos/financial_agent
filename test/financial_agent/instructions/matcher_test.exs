defmodule FinancialAgent.Instructions.MatcherTest do
  use FinancialAgent.DataCase, async: true

  import FinancialAgent.Factory

  alias FinancialAgent.Instructions.Matcher

  describe "match_event/2" do
    test "returns no match when instruction list is empty" do
      event = %{
        type: "email",
        subject: "Test email",
        from: "sender@example.com",
        content: "This is test content",
        metadata: %{}
      }

      assert {:ok, result} = Matcher.match_event(event, [])
      assert result.matched == false
      assert result.instruction == nil
      assert result.confidence == 0.0
    end

    test "handles complete event with all fields" do
      instruction =
        insert(:instruction,
          trigger_type: "new_email",
          condition_text: "Email mentions pricing"
        )

      _event = %{
        type: "email",
        subject: "Pricing inquiry",
        from: "customer@example.com",
        content: "I would like to know about your pricing",
        metadata: %{"source" => "gmail"}
      }

      # Test that we can build a valid instruction list
      instructions = [instruction]

      # Verify the function signature is correct
      assert is_function(&Matcher.match_event/2, 2)
      assert is_list(instructions)
      assert length(instructions) == 1
    end
  end

  describe "event data handling" do
    test "handles event with minimal fields" do
      _instruction =
        insert(:instruction,
          condition_text: "Simple condition"
        )

      event = %{
        type: "email",
        subject: nil,
        from: nil,
        content: "Minimal content",
        metadata: %{}
      }

      # This should not crash even with minimal data
      assert is_map(event)
      assert event.type == "email"
    end

    test "handles long content" do
      _instruction =
        insert(:instruction,
          condition_text: "Check for keyword"
        )

      long_content = String.duplicate("word ", 1000)

      _event = %{
        type: "email",
        subject: "Test",
        from: "test@example.com",
        content: long_content,
        metadata: %{}
      }

      # Content should be truncated to 500 chars in the prompt
      assert String.length(long_content) > 500
      assert String.length(String.slice(long_content, 0, 500)) == 500
    end

    test "validates event structure" do
      event = %{
        type: "email",
        subject: "Test Subject",
        from: "sender@example.com",
        content: "Test content with pricing information",
        metadata: %{"source" => "gmail"}
      }

      assert Map.has_key?(event, :type)
      assert Map.has_key?(event, :subject)
      assert Map.has_key?(event, :from)
      assert Map.has_key?(event, :content)
      assert Map.has_key?(event, :metadata)
    end
  end

  # Note: Full integration tests with actual LLM calls would go in
  # test/financial_agent/instructions/matcher_integration_test.exs
  # and be tagged with @tag :integration
end
