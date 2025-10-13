# Oban Workers

## Overview

FinancialAgent uses [Oban](https://hexdocs.pm/oban) for reliable background job processing. Oban provides:

- **Persistent job queues** backed by PostgreSQL
- **Automatic retries** with exponential backoff
- **Cron-based scheduling** for recurring tasks
- **Job monitoring** via LiveDashboard
- **Distributed processing** across multiple nodes

## Queue Configuration

Located in `config/config.exs`:

```elixir
config :financial_agent, Oban,
  repo: FinancialAgent.Repo,
  queues: [
    sync: 5,           # Gmail and HubSpot sync
    embeddings: 10,    # Vector embeddings generation
    events: 10,        # Instruction event processing
    gmail_monitor: 3,  # Gmail polling
    tasks: 5           # Stateful task execution
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # Keep jobs for 7 days
    {Oban.Plugins.Cron,
     crontab: [
       {"*/2 * * * *", FinancialAgent.Workers.GmailMonitorWorker}
     ]}
  ]
```

### Queue Priorities

1. **events** (10 workers, priority 1): Highest priority for instruction processing
2. **embeddings** (10 workers, priority 2): Medium priority for RAG
3. **tasks** (5 workers, priority 1-2): Task execution
4. **sync** (5 workers, priority 3): Background data sync
5. **gmail_monitor** (3 workers, priority 2): Email polling

## Workers

### 1. GmailSyncWorker

**Location**: `lib/financial_agent/workers/gmail_sync_worker.ex`

**Purpose**: Synchronize Gmail messages for a user

**Queue**: `sync`

**Configuration**:
```elixir
use Oban.Worker,
  queue: :sync,
  max_attempts: 3,
  priority: 3
```

**Job Arguments**:
```elixir
%{
  "user_id" => "uuid-string",
  "max_results" => 100  # Optional, defaults to 100
}
```

**Process Flow**:
1. Fetch user's Google credential
2. Build Gmail API client
3. Fetch messages (up to max_results)
4. Store messages as Chunks in database
5. Enqueue GenerateEmbeddingsWorker for each chunk

**Enqueuing**:
```elixir
GmailSyncWorker.sync_for_user(user_id)
# or
%{"user_id" => user_id}
|> GmailSyncWorker.new()
|> Oban.insert()
```

**Error Handling**:
- Retries up to 3 times with exponential backoff
- Logs errors with context
- Skips if credentials expired

---

### 2. HubspotSyncWorker

**Location**: `lib/financial_agent/workers/hubspot_sync_worker.ex`

**Purpose**: Synchronize HubSpot contacts and deals

**Queue**: `sync`

**Configuration**:
```elixir
use Oban.Worker,
  queue: :sync,
  max_attempts: 3,
  priority: 3
```

**Job Arguments**:
```elixir
%{
  "user_id" => "uuid-string",
  "resource_type" => "contacts" | "deals"
}
```

**Process Flow**:
1. Fetch user's HubSpot credential
2. Build HubSpot API client
3. Fetch resources (contacts or deals)
4. Store as Chunks with metadata
5. Enqueue GenerateEmbeddingsWorker

**Enqueuing**:
```elixir
HubspotSyncWorker.sync_contacts(user_id)
HubspotSyncWorker.sync_deals(user_id)
```

---

### 3. GenerateEmbeddingsWorker

**Location**: `lib/financial_agent/workers/generate_embeddings_worker.ex`

**Purpose**: Generate vector embeddings for text chunks

**Queue**: `embeddings`

**Configuration**:
```elixir
use Oban.Worker,
  queue: :embeddings,
  max_attempts: 3,
  priority: 2
```

**Job Arguments**:
```elixir
%{
  "chunk_id" => "uuid-string"
}
```

**Process Flow**:
1. Load chunk from database
2. Extract text content
3. Call OpenAI embeddings API
4. Store 1536-dimension vector in Pgvector
5. Update chunk with embedding

**Enqueuing**:
```elixir
%{"chunk_id" => chunk.id}
|> GenerateEmbeddingsWorker.new()
|> Oban.insert()
```

**Rate Limiting**:
- OpenAI API has rate limits
- Worker concurrency controls throughput
- Adjust `embeddings` queue workers as needed

---

### 4. EventProcessorWorker

**Location**: `lib/financial_agent/workers/event_processor_worker.ex`

**Purpose**: Process events and match against user instructions

**Queue**: `events`

**Configuration**:
```elixir
use Oban.Worker,
  queue: :events,
  max_attempts: 3,
  priority: 1
```

**Job Arguments**:
```elixir
%{
  "user_id" => "uuid-string",
  "event_type" => "email" | "contact" | "calendar",
  "event_data" => %{
    "type" => "email",
    "subject" => "...",
    "from" => "...",
    "content" => "...",
    "metadata" => %{}
  }
}
```

**Process Flow**:
1. Load user's active instructions for event type
2. Call `Matcher.match_event/2` with LLM
3. If match found (confidence > 0.7):
   - Call `Executor.execute/2`
   - Execute tools via `ToolExecutor`
4. Log result

**Enqueuing**:
```elixir
%{
  user_id: user_id,
  event_type: "email",
  event_data: email_data
}
|> EventProcessorWorker.new()
|> Oban.insert()
```

**LLM Integration**:
- Uses GPT-4o for instruction matching
- Evaluates each instruction's condition_text
- Returns confidence score (0.0 - 1.0)

---

### 5. GmailMonitorWorker

**Location**: `lib/financial_agent/workers/gmail_monitor_worker.ex`

**Purpose**: Recurring job to poll Gmail for new emails

**Queue**: `gmail_monitor`

**Configuration**:
```elixir
use Oban.Worker,
  queue: :gmail_monitor,
  max_attempts: 3,
  priority: 2
```

**Cron Schedule**: `*/2 * * * *` (every 2 minutes)

**Job Arguments**:
```elixir
%{
  "last_check" => unix_timestamp  # Optional
}
```

**Process Flow**:
1. Fetch all users with active email instructions
2. For each user:
   - Get Google credential
   - Query Gmail for emails after last check
   - Enqueue EventProcessorWorker for each new email
3. Track last check timestamp

**Queries**:
```sql
SELECT DISTINCT user_id
FROM instructions
WHERE is_active = true
AND trigger_type = 'new_email'
```

**Gmail API Query**:
```
after:YYYY/MM/DD in:inbox -in:spam -in:trash
```

**Configuration**:
Set `GMAIL_MONITOR_INTERVAL` environment variable (default: 2 minutes)

---

### 6. TaskExecutorWorker

**Location**: `lib/financial_agent/workers/task_executor_worker.ex`

**Purpose**: Execute stateful task workflows step by step

**Queue**: `tasks`

**Configuration**:
```elixir
use Oban.Worker,
  queue: :tasks,
  max_attempts: 3,
  priority: 1
```

**Job Arguments**:
```elixir
%{
  "task_id" => "uuid-string"
}
```

**Process Flow**:
1. Load task with messages
2. Call `Agent.execute_step/1`
3. Handle result:
   - `:completed` - Task done
   - `:waiting_for_input` - Pause for user
   - `:continue` - Re-enqueue worker after 1 second
4. Update task status

**Enqueuing**:
```elixir
TaskExecutorWorker.enqueue_task(task_id)
# or
TaskExecutorWorker.continue_after_input(task_id, user_input)
```

**Self-Enqueuing**:
When a task needs multiple steps, the worker re-enqueues itself:
```elixir
%{"task_id" => task_id}
|> __MODULE__.new(schedule_in: 1)
|> Oban.insert()
```

---

## Monitoring Jobs

### Using LiveDashboard

Visit `http://localhost:4000/dev/dashboard` in development:

1. Click **Oban** in sidebar
2. View queue statistics
3. See running, scheduled, and failed jobs
4. Inspect job details and errors

### Using IEx

```elixir
# List all queues
Oban.check_queue(queue: :events)

# Count jobs by state
Oban.check_queue(queue: :events, state: :available)

# List failed jobs
alias FinancialAgent.Repo
import Ecto.Query

from(j in Oban.Job,
  where: j.state == "retryable" or j.state == "discarded",
  order_by: [desc: j.scheduled_at],
  limit: 10
)
|> Repo.all()

# Retry a specific job
job = Repo.get(Oban.Job, job_id)
Oban.retry_job(job)

# Cancel scheduled jobs
from(j in Oban.Job,
  where: j.state == "scheduled" and j.worker == "MyWorker"
)
|> Repo.delete_all()
```

## Error Handling

### Automatic Retries

All workers retry failed jobs with exponential backoff:

- **Attempt 1**: Immediate
- **Attempt 2**: After ~15 seconds
- **Attempt 3**: After ~4 minutes

### Configuring Retries

```elixir
use Oban.Worker,
  max_attempts: 5,  # Increase retry count
  priority: 1
```

### Manual Intervention

For jobs that fail repeatedly:

1. Check error message in LiveDashboard
2. Fix underlying issue (API credentials, data format, etc.)
3. Retry job manually or let it retry automatically
4. If permanent failure, discard job

### Monitoring Failures

Set up alerts for:
- High failure rate in a queue
- Jobs stuck in `retryable` state
- Cron jobs not running on schedule

## Performance Tuning

### Adjusting Concurrency

Increase workers for high-throughput queues:

```elixir
config :financial_agent, Oban,
  queues: [
    events: 20,  # Increased from 10
    embeddings: 15
  ]
```

### Queue Priority

Lower priority number = higher priority:

```elixir
use Oban.Worker,
  priority: 0  # Highest priority
```

### Batch Processing

Process multiple items per job:

```elixir
def perform(%Oban.Job{args: %{"user_ids" => user_ids}}) do
  Enum.each(user_ids, &process_user/1)
end
```

### Scheduled Jobs

Delay job execution:

```elixir
%{"user_id" => user_id}
|> MyWorker.new(schedule_in: {5, :minutes})
|> Oban.insert()
```

## Best Practices

### 1. Idempotent Jobs

Design workers to be safely retried:

```elixir
def perform(%Oban.Job{args: %{"chunk_id" => chunk_id}}) do
  chunk = Repo.get!(Chunk, chunk_id)

  # Skip if already processed
  if chunk.embedding do
    :ok
  else
    generate_embedding(chunk)
  end
end
```

### 2. Small Payloads

Pass IDs, not full records:

```elixir
# Good
%{"user_id" => user.id} |> MyWorker.new()

# Bad
%{"user" => user} |> MyWorker.new()
```

### 3. Explicit Errors

Use clear error messages:

```elixir
case do_work() do
  {:ok, result} -> :ok
  {:error, :not_found} -> {:error, "User not found"}
  {:error, :api_error} -> {:error, "External API failed"}
end
```

### 4. Logging

Log important events:

```elixir
Logger.info("Processing event for user #{user_id}")
Logger.error("Failed to sync Gmail: #{inspect(error)}")
```

### 5. Timeouts

Set reasonable timeouts:

```elixir
case HTTPoison.get(url, [], timeout: 30_000) do
  {:ok, response} -> process(response)
  {:error, %{reason: :timeout}} -> {:error, :timeout}
end
```

## Testing Workers

### Unit Tests

Test worker logic directly:

```elixir
test "processes event successfully" do
  user = insert(:user)
  event_data = %{"type" => "email", "subject" => "Test"}

  args = %{
    "user_id" => user.id,
    "event_type" => "email",
    "event_data" => event_data
  }

  assert :ok = perform_job(EventProcessorWorker, args)
end
```

### Integration Tests

Test full job lifecycle:

```elixir
@tag :integration
test "enqueues and processes job" do
  user = insert(:user)

  %{"user_id" => user.id}
  |> GmailSyncWorker.new()
  |> Oban.insert!()

  # Drain queue
  assert :ok = Oban.drain_queue(queue: :sync)

  # Verify results
  assert Repo.aggregate(Chunk, :count) > 0
end
```

## Related Documentation

- [Architecture Overview](./01-architecture-overview.md)
- [Instructions System](./05-instructions-system.md)
- [Tasks System](./04-tasks-system.md)
- [RAG System](./03-rag-system.md)
