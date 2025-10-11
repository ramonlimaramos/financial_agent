defmodule FinancialAgent.Repo.Migrations.CreateChunks do
  use Ecto.Migration

  def change do
    create table(:chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :content, :text, null: false
      add :source, :string, null: false
      add :source_id, :string, null: false
      add :embedding, :vector, size: 1536
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:chunks, [:user_id])
    create index(:chunks, [:source])
    create unique_index(:chunks, [:user_id, :source, :source_id])

    # Create ivfflat index for vector similarity search
    execute "CREATE INDEX chunks_embedding_idx ON chunks USING ivfflat (embedding vector_cosine_ops)",
            "DROP INDEX IF EXISTS chunks_embedding_idx"
  end
end
