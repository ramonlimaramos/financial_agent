# RAG System (Retrieval Augmented Generation)

## Overview

The RAG system enables the AI to provide accurate, contextual responses by searching through your Gmail and HubSpot data using semantic similarity.

**Key Components:**
- **Data Collection**: Sync Gmail and HubSpot data
- **Embedding Generation**: Convert text to vectors using OpenAI
- **Vector Storage**: Store embeddings in PostgreSQL with Pgvector
- **Semantic Search**: Find relevant content using cosine similarity
- **LLM Integration**: Pass retrieved context to GPT-4o

## Architecture

```
External APIs          Database              AI Services
┌──────────┐         ┌──────────┐          ┌──────────┐
│  Gmail   │────────▶│  Chunks  │◀────────▶│  OpenAI  │
│   API    │         │  Table   │          │ Embeddings│
└──────────┘         │          │          └──────────┘
                     │ Pgvector │
┌──────────┐         │          │          ┌──────────┐
│ HubSpot  │────────▶│ Indexes  │◀────────▶│  GPT-4o  │
│   API    │         └──────────┘          │   Chat   │
└──────────┘                                └──────────┘
```

## Database Schema

### Chunks Table

```sql
CREATE TABLE chunks (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  source VARCHAR(255) NOT NULL,     -- 'gmail' or 'hubspot'
  source_id VARCHAR(255) NOT NULL,  -- External ID
  content TEXT NOT NULL,            -- Text content
  metadata JSONB DEFAULT '{}',      -- Structured data
  embedding VECTOR(1536),           -- OpenAI embedding
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,

  UNIQUE(user_id, source, source_id)
);

CREATE INDEX chunks_user_id_index ON chunks(user_id);
CREATE INDEX chunks_source_index ON chunks(source);
CREATE INDEX chunks_embedding_index ON chunks
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
```

**Schema**: `lib/financial_agent/rag/chunk.ex`

```elixir
defmodule FinancialAgent.RAG.Chunk do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chunks" do
    field :source, :string
    field :source_id, :string
    field :content, :string
    field :metadata, :map, default: %{}
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end
end
```

## Data Flow

### 1. Data Collection

#### Gmail Sync

**Worker**: `GmailSyncWorker`

```elixir
# Enqueue sync job
GmailSyncWorker.sync_for_user(user_id)
```

**Process**:
1. Fetch user's Google OAuth credential
2. Build Gmail API client with access token
3. Query for messages (up to 100 at a time)
4. For each message:
   - Extract headers (subject, from, to, date)
   - Extract text content (plain text and HTML)
   - Create Chunk with metadata
5. Enqueue `GenerateEmbeddingsWorker` for each chunk

**Chunk Structure** (Gmail):
```elixir
%Chunk{
  user_id: user.id,
  source: "gmail",
  source_id: message["id"],
  content: "Subject: #{subject}\nFrom: #{from}\n\n#{body}",
  metadata: %{
    "message_id" => "msg_123",
    "thread_id" => "thread_456",
    "subject" => "Meeting tomorrow",
    "from" => "alice@example.com",
    "to" => "bob@example.com",
    "date" => "2024-01-15T10:30:00Z",
    "labels" => ["INBOX", "IMPORTANT"]
  },
  embedding: nil  # Generated later
}
```

#### HubSpot Sync

**Worker**: `HubspotSyncWorker`

```elixir
# Sync contacts
HubspotSyncWorker.sync_contacts(user_id)

# Sync deals
HubspotSyncWorker.sync_deals(user_id)
```

**Chunk Structure** (HubSpot Contact):
```elixir
%Chunk{
  user_id: user.id,
  source: "hubspot",
  source_id: "contact_123",
  content: "Name: John Doe\nEmail: john@example.com\nCompany: Acme Inc\nPhone: 555-0123\nNotes: Interested in premium plan",
  metadata: %{
    "contact_id" => "123",
    "email" => "john@example.com",
    "company" => "Acme Inc",
    "lifecycle_stage" => "lead",
    "created_at" => "2024-01-15T10:30:00Z"
  }
}
```

### 2. Embedding Generation

**Worker**: `GenerateEmbeddingsWorker`

**Model**: `text-embedding-3-small` (1536 dimensions)

**Process**:
1. Load chunk from database
2. Call OpenAI Embeddings API:
   ```elixir
   OpenAI.embeddings(
     model: "text-embedding-3-small",
     input: chunk.content
   )
   ```
3. Extract embedding vector (1536 floats)
4. Convert to Pgvector format
5. Update chunk with embedding

**Code Example**:
```elixir
defmodule FinancialAgent.AI.Embeddings do
  def generate_embedding(text) do
    config = Application.get_env(:financial_agent, :openai)

    case OpenAI.embeddings(
      model: config[:embedding_model],
      input: text
    ) do
      {:ok, %{data: [%{"embedding" => embedding}]}} ->
        {:ok, Pgvector.new(embedding)}

      {:error, error} ->
        {:error, error}
    end
  end
end
```

**Rate Limiting**:
- OpenAI embeddings API: 3,000 requests/minute
- Worker concurrency: 10 workers in `embeddings` queue
- Automatic retries with exponential backoff

### 3. Semantic Search

**Module**: `FinancialAgent.RAG.Retrieval`

**Function**: `search_similar_chunks/3`

```elixir
def search_similar_chunks(user_id, query_text, opts \\ []) do
  limit = Keyword.get(opts, :limit, 5)
  threshold = Keyword.get(opts, :threshold, 0.7)

  # Generate embedding for query
  {:ok, query_embedding} = Embeddings.generate_embedding(query_text)

  # Search using cosine similarity
  Chunk
  |> where([c], c.user_id == ^user_id)
  |> where([c], not is_nil(c.embedding))
  |> select([c], %{
      chunk: c,
      similarity: cosine_similarity(c.embedding, ^query_embedding)
    })
  |> where([c], cosine_similarity(c.embedding, ^query_embedding) > ^threshold)
  |> order_by([c], desc: cosine_similarity(c.embedding, ^query_embedding))
  |> limit(^limit)
  |> Repo.all()
end
```

**Similarity Metrics**:
- **Cosine Similarity**: Measures angle between vectors (0 to 1)
- **Threshold**: Default 0.7 (configurable)
- **Top K**: Returns top 5 most similar chunks (configurable)

### 4. LLM Integration

**Chat Flow with RAG**:

```elixir
defmodule FinancialAgent.Chat do
  def send_message(conversation_id, user_message) do
    conversation = get_conversation!(conversation_id)

    # 1. Search for relevant context
    {:ok, relevant_chunks} =
      Retrieval.search_similar_chunks(
        conversation.user_id,
        user_message,
        limit: 5
      )

    # 2. Build context from chunks
    context = build_context(relevant_chunks)

    # 3. Build messages for LLM
    messages = [
      %{
        role: "system",
        content: """
        You are a helpful AI assistant with access to the user's Gmail and HubSpot data.

        Use the following context to answer questions:

        #{context}

        If the context doesn't contain relevant information, say so.
        Always cite which emails or contacts you're referencing.
        """
      },
      ...conversation_history,
      %{role: "user", content: user_message}
    ]

    # 4. Call LLM
    {:ok, response} = LLMClient.chat_completion(messages)

    # 5. Save messages
    save_messages(conversation, user_message, response)
  end

  defp build_context(chunks) do
    chunks
    |> Enum.map(fn %{chunk: chunk, similarity: sim} ->
      """
      [Source: #{chunk.source}, Similarity: #{Float.round(sim, 2)}]
      #{chunk.content}
      ---
      """
    end)
    |> Enum.join("\n\n")
  end
end
```

## Performance Optimization

### Indexing Strategy

**IVFFlat Index** (Inverted File Flat):

```sql
CREATE INDEX chunks_embedding_index ON chunks
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
```

**Trade-offs**:
- **lists = 100**: Good balance for 10,000-100,000 vectors
- Increase `lists` for larger datasets
- Decrease for smaller datasets

**Index Build**:
```sql
-- Check index stats
SELECT * FROM pg_stat_user_indexes
WHERE indexrelname = 'chunks_embedding_index';

-- Rebuild if needed
REINDEX INDEX chunks_embedding_index;
```

### Query Optimization

**Pre-filter by User**:
```elixir
# Good - filters before vector search
Chunk
|> where([c], c.user_id == ^user_id)
|> where([c], not is_nil(c.embedding))
|> order_by([c], desc: cosine_similarity(...))

# Bad - vector search across all users
Chunk
|> where([c], not is_nil(c.embedding))
|> order_by([c], desc: cosine_similarity(...))
|> where([c], c.user_id == ^user_id)
```

**Limit Results**:
```elixir
# Only retrieve what you need
|> limit(5)
```

**Select Specific Fields**:
```elixir
# Only select needed columns
|> select([c], %{
    id: c.id,
    content: c.content,
    metadata: c.metadata,
    similarity: cosine_similarity(...)
  })
```

### Caching

**Query Embedding Cache**:
```elixir
defmodule Retrieval do
  @cache_ttl 5 * 60 * 1000  # 5 minutes

  def search_similar_chunks(user_id, query, opts) do
    cache_key = {:embedding, query}

    query_embedding =
      case Cachex.get(:embeddings_cache, cache_key) do
        {:ok, nil} ->
          {:ok, embedding} = Embeddings.generate_embedding(query)
          Cachex.put(:embeddings_cache, cache_key, embedding, ttl: @cache_ttl)
          embedding

        {:ok, embedding} ->
          embedding
      end

    # Use cached embedding for search
    do_search(user_id, query_embedding, opts)
  end
end
```

## Monitoring & Debugging

### Check Embedding Coverage

```elixir
# Count chunks with/without embeddings
import Ecto.Query
alias FinancialAgent.{Repo, RAG.Chunk}

Repo.aggregate(
  from(c in Chunk, where: not is_nil(c.embedding)),
  :count
)

Repo.aggregate(
  from(c in Chunk, where: is_nil(c.embedding)),
  :count
)
```

### Test Similarity Search

```elixir
# In IEx
alias FinancialAgent.RAG.Retrieval

# Search for relevant content
{:ok, results} = Retrieval.search_similar_chunks(
  user_id,
  "emails about pricing",
  limit: 5
)

# Inspect results
Enum.each(results, fn %{chunk: chunk, similarity: sim} ->
  IO.puts("Similarity: #{sim}")
  IO.puts("Source: #{chunk.source}")
  IO.puts("Content: #{String.slice(chunk.content, 0..100)}...")
  IO.puts("---")
end)
```

### Measure Query Performance

```elixir
# Time a search query
:timer.tc(fn ->
  Retrieval.search_similar_chunks(user_id, "test query")
end)
# Returns: {microseconds, result}
```

### Monitor Queue Backlogs

```elixir
# Check embeddings queue
Oban.check_queue(queue: :embeddings)

# List pending jobs
from(j in Oban.Job,
  where: j.queue == "embeddings" and j.state == "available",
  select: count(j.id)
)
|> Repo.one()
```

## Best Practices

### 1. Chunk Size

Keep chunks to 500-1000 tokens:
```elixir
def chunk_text(text) do
  text
  |> String.split("\n\n")
  |> Enum.chunk_every(3)
  |> Enum.map(&Enum.join(&1, "\n\n"))
end
```

### 2. Metadata Strategy

Store queryable fields in metadata:
```elixir
%{
  "source" => "gmail",
  "date" => "2024-01-15",
  "from" => "alice@example.com",
  "labels" => ["IMPORTANT"]
}
```

### 3. Incremental Updates

Only sync new/changed data:
```elixir
def sync_new_messages(user_id) do
  last_sync = get_last_sync_time(user_id)
  query = "after:#{format_date(last_sync)}"

  fetch_messages(query)
end
```

### 4. Error Handling

Handle embedding failures gracefully:
```elixir
def generate_embeddings_batch(chunks) do
  Enum.map(chunks, fn chunk ->
    case generate_embedding(chunk) do
      {:ok, _} -> :ok
      {:error, error} ->
        Logger.error("Failed to embed chunk #{chunk.id}: #{inspect(error)}")
        :error
    end
  end)
end
```

### 5. Testing

Test with known similar content:
```elixir
test "finds similar emails about meetings" do
  user = insert(:user)

  # Insert test chunks
  chunk1 = insert(:chunk,
    user: user,
    content: "Meeting tomorrow at 2pm",
    embedding: generate_test_embedding("meeting tomorrow")
  )

  chunk2 = insert(:chunk,
    user: user,
    content: "Schedule a call next week",
    embedding: generate_test_embedding("schedule call")
  )

  # Search
  {:ok, results} = Retrieval.search_similar_chunks(
    user.id,
    "upcoming meetings"
  )

  # Should find chunk1 first
  assert hd(results).chunk.id == chunk1.id
end
```

## Troubleshooting

### No Results Returned

**Possible Causes**:
1. Embeddings not generated yet
2. Similarity threshold too high
3. Query too different from content

**Solutions**:
```elixir
# Check if embeddings exist
Repo.aggregate(
  from(c in Chunk, where: c.user_id == ^user_id and not is_nil(c.embedding)),
  :count
)

# Lower threshold
search_similar_chunks(user_id, query, threshold: 0.5)

# Check raw similarities
results = search_similar_chunks(user_id, query, limit: 10, threshold: 0.0)
Enum.map(results, & &1.similarity)
```

### Slow Queries

**Possible Causes**:
1. Missing index
2. Too many chunks
3. No user_id filter

**Solutions**:
```sql
-- Verify index exists
\d chunks

-- Rebuild index
REINDEX INDEX chunks_embedding_index;

-- Analyze query plan
EXPLAIN ANALYZE
SELECT * FROM chunks
WHERE user_id = '...'
ORDER BY embedding <-> '[...]'
LIMIT 5;
```

### High Embedding Costs

**Monitor Usage**:
```elixir
# Count embedding jobs
from(j in Oban.Job,
  where: j.worker == "GenerateEmbeddingsWorker",
  where: j.inserted_at > ago(1, "day"),
  select: count(j.id)
)
|> Repo.one()
```

**Optimize**:
- Skip re-embedding unchanged content
- Batch embedding requests
- Use smaller embedding model for non-critical use cases

## Related Documentation

- [Architecture Overview](./01-architecture-overview.md)
- [Oban Workers](./02-oban-workers.md)
- [Events & Tools](./06-events-and-tools.md)
