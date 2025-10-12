defmodule FinancialAgent.RAG do
  @moduledoc """
  The RAG (Retrieval Augmented Generation) context for managing chunks and embeddings.
  """

  import Ecto.Query, warn: false
  alias FinancialAgent.Repo
  alias FinancialAgent.RAG.Chunk

  @doc """
  Creates a chunk without an embedding.

  The embedding will be generated asynchronously by a worker.
  """
  @spec create_chunk(map()) :: {:ok, Chunk.t()} | {:error, Ecto.Changeset.t()}
  def create_chunk(attrs \\ %{}) do
    %Chunk{}
    |> Chunk.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:content, :updated_at]},
      conflict_target: [:user_id, :source, :source_id]
    )
  end

  @doc """
  Updates a chunk's embedding.
  """
  @spec update_chunk_embedding(Chunk.t(), Pgvector.t()) ::
          {:ok, Chunk.t()} | {:error, Ecto.Changeset.t()}
  def update_chunk_embedding(%Chunk{} = chunk, embedding) do
    chunk
    |> Chunk.update_embedding(embedding)
    |> Repo.update()
  end

  @doc """
  Gets a chunk by ID.
  """
  @spec get_chunk(Ecto.UUID.t()) :: Chunk.t() | nil
  def get_chunk(id) do
    Repo.get(Chunk, id)
  end

  @doc """
  Lists all chunks for a user.
  """
  @spec list_user_chunks(Ecto.UUID.t()) :: [Chunk.t()]
  def list_user_chunks(user_id) do
    Chunk
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists chunks for a user by source (gmail or hubspot).
  """
  @spec list_user_chunks_by_source(Ecto.UUID.t(), String.t()) :: [Chunk.t()]
  def list_user_chunks_by_source(user_id, source) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.source == ^source)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Searches for similar chunks using vector similarity.

  Returns chunks ordered by similarity (most similar first).
  """
  @spec search_similar_chunks(Ecto.UUID.t(), Pgvector.t(), integer()) :: [Chunk.t()]
  def search_similar_chunks(user_id, query_embedding, limit \\ 5) do
    Chunk
    |> where([c], c.user_id == ^user_id)
    |> where([c], not is_nil(c.embedding))
    |> order_by([c], fragment("? <=> ?", c.embedding, ^query_embedding))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Counts chunks for a user.
  """
  @spec count_user_chunks(Ecto.UUID.t()) :: integer()
  def count_user_chunks(user_id) do
    Chunk
    |> where([c], c.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Counts chunks for a user by source.
  """
  @spec count_user_chunks_by_source(Ecto.UUID.t(), String.t()) :: integer()
  def count_user_chunks_by_source(user_id, source) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.source == ^source)
    |> Repo.aggregate(:count)
  end

  @doc """
  Deletes all chunks for a user.
  """
  @spec delete_user_chunks(Ecto.UUID.t()) :: {integer(), nil}
  def delete_user_chunks(user_id) do
    Chunk
    |> where([c], c.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes chunks for a user by source.
  """
  @spec delete_user_chunks_by_source(Ecto.UUID.t(), String.t()) :: {integer(), nil}
  def delete_user_chunks_by_source(user_id, source) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.source == ^source)
    |> Repo.delete_all()
  end
end
