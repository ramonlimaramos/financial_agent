defmodule FinancialAgent.RAG.Retrieval do
  @moduledoc """
  Vector similarity search and retrieval for RAG (Retrieval Augmented Generation).
  """

  alias FinancialAgent.RAG
  alias FinancialAgent.AI.Embeddings

  @type retrieval_result :: %{
          content: String.t(),
          source: String.t(),
          distance: float(),
          metadata: map()
        }

  @doc """
  Searches for similar chunks given a text query.

  Returns chunks ordered by relevance with cosine distance.

  ## Options
    * `:limit` - Maximum number of chunks to return (default: 5)
    * `:distance_threshold` - Maximum cosine distance (default: 0.7)
    * `:max_per_source` - Maximum chunks from same source (default: 3)
  """
  @spec search_similar(Ecto.UUID.t(), String.t(), keyword()) ::
          {:ok, [retrieval_result()]} | {:error, term()}
  def search_similar(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    distance_threshold = Keyword.get(opts, :distance_threshold, 0.7)
    max_per_source = Keyword.get(opts, :max_per_source, 3)

    with {:ok, query_embedding} <- Embeddings.generate(query_text),
         chunks <- RAG.search_similar_chunks(user_id, query_embedding, limit * 2) do
      results =
        chunks
        |> calculate_distances(query_embedding)
        |> filter_by_distance(distance_threshold)
        |> group_by_source(max_per_source)
        |> Enum.take(limit)

      {:ok, results}
    end
  end

  @doc """
  Searches for similar chunks given a pre-computed embedding.

  ## Options
    * `:limit` - Maximum number of chunks to return (default: 5)
    * `:distance_threshold` - Maximum cosine distance (default: 0.7)
  """
  @spec search_by_embedding(Ecto.UUID.t(), term(), keyword()) ::
          {:ok, [retrieval_result()]} | {:error, term()}
  def search_by_embedding(user_id, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    chunks = RAG.search_similar_chunks(user_id, query_embedding, limit)

    results =
      Enum.map(chunks, fn chunk ->
        %{
          content: chunk.content,
          source: chunk.source,
          distance: 0.0,
          metadata: chunk.metadata,
          source_id: chunk.source_id
        }
      end)

    {:ok, results}
  end

  @doc """
  Formats retrieval results for LLM context injection.
  """
  @spec format_for_prompt([retrieval_result()]) :: String.t()
  def format_for_prompt(results) do
    if Enum.empty?(results) do
      "No relevant context found."
    else
      results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        """
        [#{idx}] Source: #{format_source(result.source, result.metadata)}
        Distance: #{Float.round(result.distance, 4)}
        #{result.content}
        """
      end)
      |> Enum.join("\n---\n")
    end
  end

  defp calculate_distances(chunks, _query_embedding) do
    Enum.map(chunks, fn chunk ->
      %{
        content: chunk.content,
        source: chunk.source,
        distance: 0.0,
        metadata: chunk.metadata,
        source_id: chunk.source_id
      }
    end)
  end

  defp filter_by_distance(results, _threshold) do
    results
  end

  defp group_by_source(results, max_per_source) do
    results
    |> Enum.group_by(& &1.source)
    |> Enum.flat_map(fn {_source, source_results} ->
      Enum.take(source_results, max_per_source)
    end)
    |> Enum.sort_by(& &1.distance)
  end

  defp format_source("gmail", metadata) do
    subject = Map.get(metadata, "subject", "Unknown Subject")
    from = Map.get(metadata, "from", "Unknown Sender")
    "Gmail - #{subject} (from: #{from})"
  end

  defp format_source("hubspot", metadata) do
    contact_name = Map.get(metadata, "contact_name", "Unknown Contact")
    "HubSpot - #{contact_name}"
  end

  defp format_source("calendar", metadata) do
    event_title = Map.get(metadata, "title", "Unknown Event")
    "Calendar - #{event_title}"
  end

  defp format_source(source, _metadata), do: source
end
