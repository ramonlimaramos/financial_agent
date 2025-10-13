defmodule FinancialAgent.AI.Embeddings do
  @moduledoc """
  Generates embeddings using OpenAI's API for vector search.
  """

  @doc """
  Generates an embedding vector for the given text using OpenAI's API.

  Returns a Pgvector-compatible vector.
  """
  @spec generate(String.t()) :: {:ok, Pgvector.t()} | {:error, term()}
  def generate(text) do
    config = Application.get_env(:financial_agent, :openai, [])
    api_key = Keyword.get(config, :api_key) || System.get_env("OPENAI_API_KEY")
    model = Keyword.get(config, :embedding_model, "text-embedding-3-small")

    case OpenAI.embeddings(model: model, input: text, api_key: api_key) do
      {:ok, %{data: [%{"embedding" => embedding} | _]}} ->
        {:ok, Pgvector.new(embedding)}

      {:error, reason} ->
        {:error, {:openai_error, reason}}
    end
  end

  @doc """
  Generates embeddings for multiple texts in batch.
  """
  @spec generate_batch([String.t()]) :: {:ok, [Pgvector.t()]} | {:error, term()}
  def generate_batch(texts) when is_list(texts) do
    config = Application.get_env(:financial_agent, :openai, [])
    api_key = Keyword.get(config, :api_key) || System.get_env("OPENAI_API_KEY")
    model = Keyword.get(config, :embedding_model, "text-embedding-3-small")

    case OpenAI.embeddings(model: model, input: texts, api_key: api_key) do
      {:ok, %{data: embeddings}} ->
        vectors =
          embeddings
          |> Enum.map(fn %{"embedding" => embedding} -> Pgvector.new(embedding) end)

        {:ok, vectors}

      {:error, reason} ->
        {:error, {:openai_error, reason}}
    end
  end
end
