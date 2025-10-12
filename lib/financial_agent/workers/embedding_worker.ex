defmodule FinancialAgent.Workers.EmbeddingWorker do
  @moduledoc """
  Oban worker that generates embeddings for a chunk using OpenAI's API.

  This worker:
  1. Fetches the chunk from the database
  2. Calls OpenAI's embeddings API to generate a vector
  3. Updates the chunk with the embedding vector

  ## Options
  - `:chunk_id` (required) - The UUID of the chunk to generate embeddings for
  """

  use Oban.Worker,
    queue: :embeddings,
    max_attempts: 3,
    unique: [
      period: 60,
      states: [:available, :scheduled, :executing]
    ]

  alias FinancialAgent.RAG
  alias FinancialAgent.RAG.Chunk

  require Logger

  @openai_api_url "https://api.openai.com/v1/embeddings"
  @embedding_model "text-embedding-3-small"
  @embedding_dimensions 1536

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chunk_id" => chunk_id}}) do
    Logger.info("Starting embedding generation for chunk #{chunk_id}")

    with {:ok, chunk} <- get_chunk(chunk_id),
         {:ok, embedding} <- generate_embedding(chunk.content),
         {:ok, _updated_chunk} <- update_chunk_embedding(chunk, embedding) do
      Logger.info("Embedding generated successfully for chunk #{chunk_id}")
      :ok
    else
      {:error, :chunk_not_found} ->
        Logger.warning("Chunk #{chunk_id} not found")
        {:error, :chunk_not_found}

      {:error, reason} = error ->
        Logger.error("Embedding generation failed for chunk #{chunk_id}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp get_chunk(chunk_id) do
    case RAG.get_chunk(chunk_id) do
      %Chunk{} = chunk -> {:ok, chunk}
      nil -> {:error, :chunk_not_found}
    end
  end

  defp generate_embedding(text) do
    api_key = get_openai_api_key!()

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      input: text,
      model: @embedding_model,
      dimensions: @embedding_dimensions
    }

    case HTTPoison.post(@openai_api_url, Jason.encode!(body), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => [%{"embedding" => embedding}]}} ->
            {:ok, embedding}

          {:ok, unexpected} ->
            Logger.error("Unexpected OpenAI API response: #{inspect(unexpected)}")
            {:error, :unexpected_response}

          {:error, decode_error} ->
            Logger.error("Failed to decode OpenAI API response: #{inspect(decode_error)}")
            {:error, :decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("OpenAI API error: #{status_code} - #{response_body}")
        {:error, {:api_error, status_code, response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("OpenAI API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_chunk_embedding(chunk, embedding) do
    RAG.update_chunk_embedding(chunk, embedding)
  end

  defp get_openai_api_key! do
    System.get_env("OPENAI_API_KEY") ||
      raise "OPENAI_API_KEY environment variable is not set"
  end
end
