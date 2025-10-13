defmodule FinancialAgent.AI.LLMClient do
  @moduledoc """
  OpenAI LLM client with support for chat completions and streaming.
  """

  @type message :: %{
          role: String.t(),
          content: String.t(),
          tool_calls: map() | nil
        }

  @type completion_opts :: [
          model: String.t(),
          temperature: float(),
          max_tokens: integer(),
          tools: [map()],
          stream: boolean()
        ]

  @doc """
  Performs a chat completion with OpenAI without streaming.

  ## Options
    * `:model` - Model to use (default: "gpt-4-turbo-preview")
    * `:temperature` - Sampling temperature (default: 0.7)
    * `:max_tokens` - Maximum tokens in response (default: 1000)
    * `:tools` - List of available tools for function calling
  """
  @spec chat_completion([message()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def chat_completion(messages, opts \\ []) do
    config = build_config(opts)

    request_params = [
      model: config.model,
      messages: messages,
      temperature: config.temperature,
      max_tokens: config.max_tokens
    ]

    request_params =
      if config.tools && length(config.tools) > 0 do
        Keyword.put(request_params, :tools, config.tools)
      else
        request_params
      end

    case OpenAI.chat_completion(request_params) do
      {:ok, response} ->
        {:ok, parse_completion_response(response)}

      {:error, reason} ->
        {:error, {:openai_error, reason}}
    end
  end

  @doc """
  Performs a chat completion with streaming support.

  Returns a stream that yields chunks of the response.

  ## Options
    * `:model` - Model to use (default: "gpt-4-turbo-preview")
    * `:temperature` - Sampling temperature (default: 0.7)
    * `:max_tokens` - Maximum tokens in response (default: 1000)
  """
  @spec chat_completion_stream([message()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def chat_completion_stream(messages, opts \\ []) do
    config = build_config(opts)

    request_params = [
      model: config.model,
      messages: messages,
      temperature: config.temperature,
      max_tokens: config.max_tokens,
      stream: true
    ]

    result = OpenAI.chat_completion(request_params)

    case result do
      {:ok, stream} ->
        parsed_stream =
          stream
          |> Stream.map(&parse_stream_chunk/1)
          |> Stream.reject(&is_nil/1)

        {:ok, parsed_stream}

      %Stream{} = stream ->
        # OpenAI returns stream directly, not wrapped in {:ok, stream}
        parsed_stream =
          stream
          |> Stream.map(&parse_stream_chunk/1)
          |> Stream.reject(&is_nil/1)

        {:ok, parsed_stream}

      {:error, reason} ->
        {:error, {:openai_error, reason}}

      error ->
        {:error, {:unexpected_response, error}}
    end
  end

  @doc """
  Estimates token count for messages (approximate).
  """
  @spec estimate_tokens([message()]) :: integer()
  def estimate_tokens(messages) do
    messages
    |> Enum.map(fn msg -> String.length(msg.content) end)
    |> Enum.sum()
    |> Kernel.div(4)
  end

  defp build_config(opts) do
    app_config = Application.get_env(:financial_agent, :openai, [])

    api_key =
      Keyword.get(opts, :api_key) || Keyword.get(app_config, :api_key) ||
        System.get_env("OPENAI_API_KEY")

    # Get model from config, fallback to gpt-4o (128K context window)
    default_model = Keyword.get(app_config, :chat_model, "gpt-4o")

    %{
      api_key: api_key,
      model: Keyword.get(opts, :model, default_model),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 4000),
      tools: Keyword.get(opts, :tools, [])
    }
  end

  defp parse_completion_response(response) do
    choice = List.first(response.choices)

    %{
      content: choice["message"]["content"],
      role: choice["message"]["role"],
      tool_calls: Map.get(choice["message"], "tool_calls"),
      finish_reason: choice["finish_reason"],
      tokens_used: get_in(response, [:usage, :total_tokens]) || 0
    }
  end

  defp parse_stream_chunk(chunk) do
    # Log the chunk for debugging
    require Logger
    Logger.debug("Received stream chunk: #{inspect(chunk)}")

    case chunk do
      %{"choices" => [%{"delta" => delta} | _]} ->
        content = Map.get(delta, "content")
        tool_calls = Map.get(delta, "tool_calls")

        cond do
          content && content != "" -> {:content, content}
          tool_calls -> {:tool_calls, tool_calls}
          true -> nil
        end

      # Handle string chunks (data: [DONE] or JSON strings)
      "[DONE]" ->
        nil

      chunk when is_binary(chunk) ->
        # Try to parse as JSON
        case Jason.decode(chunk) do
          {:ok, parsed} -> parse_stream_chunk(parsed)
          {:error, _} -> nil
        end

      _ ->
        Logger.debug("Unhandled chunk format: #{inspect(chunk)}")
        nil
    end
  end
end
