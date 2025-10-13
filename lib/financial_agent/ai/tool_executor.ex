defmodule FinancialAgent.AI.ToolExecutor do
  @moduledoc """
  Executes tool calls requested by the LLM.
  Routes tool calls to appropriate implementations.
  """

  alias FinancialAgent.Tools.HubspotLookup

  @type tool_context :: %{
          user_id: Ecto.UUID.t(),
          conversation_id: Ecto.UUID.t()
        }

  @doc """
  Executes a tool call and returns the result.
  """
  @spec execute(String.t(), map(), tool_context()) ::
          {:ok, map()} | {:error, term()}
  def execute(tool_name, args, context) do
    case tool_name do
      "get_hubspot_contact" ->
        name = Map.get(args, "name")
        HubspotLookup.call(name, context.user_id)

      _ ->
        {:error, {:unknown_tool, tool_name}}
    end
  end

  @doc """
  Executes multiple tool calls in parallel.
  """
  @spec execute_batch([{String.t(), map()}], tool_context()) :: [
          {:ok, map()} | {:error, term()}
        ]
  def execute_batch(tool_calls, context) do
    tool_calls
    |> Task.async_stream(
      fn {tool_name, args} ->
        execute(tool_name, args, context)
      end,
      timeout: 30_000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:execution_timeout, reason}}
    end)
  end

  @doc """
  Formats tool results for inclusion in LLM messages.
  """
  @spec format_tool_result(String.t(), {:ok, map()} | {:error, term()}) ::
          map()
  def format_tool_result(tool_call_id, result) do
    case result do
      {:ok, data} ->
        %{
          role: "tool",
          tool_call_id: tool_call_id,
          content: Jason.encode!(data)
        }

      {:error, reason} ->
        %{
          role: "tool",
          tool_call_id: tool_call_id,
          content: Jason.encode!(%{error: inspect(reason)})
        }
    end
  end
end
