defmodule FinancialAgent.RAG.Chunk do
  @moduledoc """
  Chunk schema for storing text content with vector embeddings for RAG.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          content: String.t(),
          source: String.t(),
          source_id: String.t(),
          # embedding: Pgvector.t() | nil,  # Temporarily disabled
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chunks" do
    field :content, :string
    field :source, :string
    field :source_id, :string
    # Temporarily commented out until pgvector is enabled on database
    # field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAgent.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new chunk.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(chunk, attrs) do
    chunk
    # Removed :embedding from cast until pgvector is enabled
    |> cast(attrs, [:user_id, :content, :source, :source_id, :metadata])
    |> validate_required([:user_id, :content, :source, :source_id])
    |> validate_inclusion(:source, ["gmail", "hubspot"])
    |> unique_constraint([:user_id, :source, :source_id])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating embedding after generation.
  """
  @spec update_embedding(t(), Pgvector.t()) :: Ecto.Changeset.t()
  def update_embedding(chunk, embedding) do
    chunk
    |> change(embedding: embedding)
  end
end
