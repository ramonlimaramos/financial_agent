defmodule FinancialAgent.Instructions.Matcher do
  @moduledoc """
  Matches incoming events against user instructions using LLM-based evaluation.

  This module determines if an event (like a new email) matches any of the user's
  active instructions by asking an LLM to evaluate the conditions.
  """

  alias FinancialAgent.AI.LLMClient
  alias FinancialAgent.Instructions.Instruction

  @type event_data :: %{
          type: String.t(),
          subject: String.t() | nil,
          from: String.t() | nil,
          content: String.t(),
          metadata: map()
        }

  @type match_result :: %{
          matched: boolean(),
          instruction: Instruction.t() | nil,
          confidence: float()
        }

  @doc """
  Evaluates an event against a list of instructions and returns the first match.

  ## Examples

      iex> event = %{type: "email", subject: "Pricing question", ...}
      iex> instructions = [%Instruction{condition_text: "email mentions pricing"}]
      iex> match_event(event, instructions)
      {:ok, %{matched: true, instruction: %Instruction{}, confidence: 0.95}}

      iex> match_event(event, [])
      {:ok, %{matched: false, instruction: nil, confidence: 0.0}}
  """
  @spec match_event(event_data(), [Instruction.t()]) ::
          {:ok, match_result()} | {:error, term()}
  def match_event(_event, []), do: {:ok, %{matched: false, instruction: nil, confidence: 0.0}}

  def match_event(event, instructions) do
    # Try each instruction until we find a match
    results =
      instructions
      |> Enum.map(fn instruction ->
        case evaluate_single_instruction(event, instruction) do
          {:ok, match_result} -> {instruction, match_result}
          {:error, _reason} -> {instruction, %{matched: false, confidence: 0.0}}
        end
      end)

    # Find the best match (highest confidence above threshold)
    best_match =
      results
      |> Enum.filter(fn {_instruction, result} ->
        result.matched && result.confidence >= 0.7
      end)
      |> Enum.max_by(fn {_instruction, result} -> result.confidence end, fn -> nil end)

    case best_match do
      {instruction, result} ->
        {:ok, Map.put(result, :instruction, instruction)}

      nil ->
        {:ok, %{matched: false, instruction: nil, confidence: 0.0}}
    end
  end

  @doc """
  Evaluates a single instruction against an event.
  """
  @spec evaluate_single_instruction(event_data(), Instruction.t()) ::
          {:ok, %{matched: boolean(), confidence: float()}} | {:error, term()}
  def evaluate_single_instruction(event, instruction) do
    prompt = build_evaluation_prompt(event, instruction)

    messages = [
      %{
        role: "system",
        content: """
        You are an instruction matcher. Evaluate if the given event matches the user's instruction.
        Respond with JSON in this exact format:
        {"matched": true/false, "confidence": 0.0-1.0, "reasoning": "brief explanation"}

        Be precise. Only match if the condition is clearly satisfied.
        """
      },
      %{role: "user", content: prompt}
    ]

    case LLMClient.chat_completion(messages, model: "gpt-4o", temperature: 0.0, max_tokens: 200) do
      {:ok, response} ->
        parse_evaluation_response(response)

      {:error, reason} ->
        {:error, {:llm_error, reason}}
    end
  end

  defp build_evaluation_prompt(event, instruction) do
    """
    ## Event Details
    Type: #{event.type}
    #{if event.subject, do: "Subject: #{event.subject}\n", else: ""}#{if event.from, do: "From: #{event.from}\n", else: ""}Content: #{String.slice(event.content, 0, 500)}
    #{if map_size(event.metadata) > 0, do: "Metadata: #{inspect(event.metadata)}", else: ""}

    ## Instruction to Match
    Trigger Type: #{instruction.trigger_type}
    Condition: #{instruction.condition_text}

    Does this event match the instruction's condition?
    """
  end

  defp parse_evaluation_response(response) do
    content = response.content || ""

    case Jason.decode(content) do
      {:ok, %{"matched" => matched, "confidence" => confidence}} ->
        {:ok, %{matched: matched, confidence: confidence}}

      {:ok, _other} ->
        # Fallback: check if response contains "true" or "false"
        matched = String.contains?(String.downcase(content), "true")
        {:ok, %{matched: matched, confidence: if(matched, do: 0.5, else: 0.0)}}

      {:error, _reason} ->
        # Try to parse from natural language
        matched = String.contains?(String.downcase(content), ["yes", "match", "true"])
        {:ok, %{matched: matched, confidence: if(matched, do: 0.5, else: 0.0)}}
    end
  end
end
