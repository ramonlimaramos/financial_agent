# Tasks System (Stateful Workflows)

## Overview

The Tasks system enables complex, multi-turn workflows that require:
- Multiple steps with state tracking
- LLM-based decision making
- Tool execution
- User interaction and input
- Conversation history

**Example Use Cases:**
- Schedule a meeting (requires finding availability, sending invites)
- Compose and send an email (requires drafting, user approval, sending)
- Research a topic (requires multiple searches, synthesis)
- Data analysis (requires querying, processing, visualization)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Task Creation                           │
│  (from Instruction or Manual)                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              TaskExecutorWorker (Oban)                       │
│                                                              │
│  1. Load task + conversation history                         │
│  2. Call Agent.execute_step                                  │
│  3. Handle result                                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Tasks.Agent                                 │
│                                                              │
│  1. Analyze task and conversation                            │
│  2. Decide next action via LLM                               │
│  3. Execute tools or request input                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
         ▼             ▼             ▼
┌──────────────┐  ┌─────────┐  ┌──────────────┐
│ Tool Execute │  │ Request │  │  Complete    │
│              │  │  Input  │  │   Task       │
└──────────────┘  └─────────┘  └──────────────┘
```

## Database Schema

### Tasks Table

```sql
CREATE TABLE tasks (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  task_type VARCHAR(50) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  context JSONB DEFAULT '{}',
  result JSONB,
  error TEXT,
  parent_instruction_id UUID REFERENCES instructions(id),
  completed_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX tasks_user_id_index ON tasks(user_id);
CREATE INDEX tasks_status_index ON tasks(status);
CREATE INDEX tasks_user_id_status_index ON tasks(user_id, status);
```

### Task Messages Table

```sql
CREATE TABLE task_messages (
  id UUID PRIMARY KEY,
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL,
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX task_messages_task_id_index ON tasks_messages(task_id);
CREATE INDEX task_messages_task_id_inserted_at_index
  ON task_messages(task_id, inserted_at);
```

## Task Lifecycle

### State Machine

```
pending ────────────────┐
   │                    │
   │                    ▼
   └────────────▶ in_progress ────────▶ completed
                      │
                      ├────────▶ waiting_for_input ──┐
                      │                │             │
                      │                └─────────────┘
                      │
                      ├────────▶ failed
                      │
                      └────────▶ cancelled
```

**Valid Transitions:**
- `pending` → `in_progress`, `cancelled`
- `in_progress` → `waiting_for_input`, `completed`, `failed`, `cancelled`
- `waiting_for_input` → `in_progress`, `cancelled`
- `completed`, `failed`, `cancelled` → (terminal states, no transitions)

**Module**: `lib/financial_agent/tasks/state_machine.ex`

```elixir
# Check if transition is valid
StateMachine.can_transition?("pending", "in_progress")
# => true

# Get valid next states
StateMachine.next_statuses("in_progress")
# => ["waiting_for_input", "completed", "failed", "cancelled"]

# Check if state is terminal
StateMachine.terminal_state?("completed")
# => true
```

### Task Types

Defined in `Task` schema:

```elixir
@task_types [
  "schedule_meeting",
  "compose_email",
  "research",
  "data_analysis",
  "custom"
]
```

Each type has specific behavior in the `Agent` module for:
- System prompts
- Available tools
- Decision making logic

## Creating Tasks

### From Instructions

When an instruction action executes, it can create a task:

```elixir
# In Executor
{:ok, task} = Tasks.create_task(%{
  user_id: user_id,
  title: "Schedule team meeting",
  description: "Schedule a meeting with the engineering team for next week",
  task_type: "schedule_meeting",
  context: %{
    "participants" => ["alice@example.com", "bob@example.com"],
    "duration" => "1 hour"
  },
  parent_instruction_id: instruction.id
})

# Enqueue for execution
TaskExecutorWorker.enqueue_task(task.id)
```

### Manual Creation

Users can create tasks directly via UI or API:

```elixir
{:ok, task} = Tasks.create_task(%{
  user_id: current_user.id,
  title: "Research competitor pricing",
  task_type: "research",
  context: %{
    "competitors" => ["Company A", "Company B"]
  }
})

TaskExecutorWorker.enqueue_task(task.id)
```

## Task Execution

### Agent Module

**Location**: `lib/financial_agent/tasks/agent.ex`

The `Agent` module orchestrates task execution using GPT-4o.

#### execute_step/1

Main execution function:

```elixir
@spec execute_step(Task.t()) ::
  {:ok, :completed, map()} |
  {:ok, :waiting_for_input, String.t()} |
  {:ok, :continue} |
  {:error, term()}

def execute_step(task) do
  # 1. Validate transition
  :ok = StateMachine.validate_transition(task, "in_progress")

  # 2. Update status
  {:ok, task} = Tasks.update_task_status(task, "in_progress")

  # 3. Get conversation history
  conversation = Tasks.get_task_conversation(task.id)

  # 4. Analyze and decide next action
  {:ok, decision} = analyze_and_decide(task, conversation)

  # 5. Execute decision
  {:ok, result} = execute_decision(task, decision)

  # 6. Handle result
  handle_execution_result(task, result)
end
```

#### Decision Types

The LLM can make three types of decisions:

**1. Use Tool**
```json
{
  "action": "use_tool",
  "tool": "send_email",
  "arguments": {
    "to": "alice@example.com",
    "subject": "Meeting Invite",
    "body": "Let's meet tomorrow at 2pm"
  }
}
```

**2. Request Input**
```json
{
  "action": "request_input",
  "question": "What time works best for the meeting?"
}
```

**3. Complete**
```json
{
  "action": "complete",
  "result": {
    "meeting_scheduled": true,
    "time": "2024-01-16 14:00",
    "attendees": ["alice@example.com"]
  }
}
```

### System Prompts

The Agent builds task-specific system prompts:

```elixir
defp build_system_prompt(task) do
  """
  You are an AI agent helping to complete a task of type: #{task.task_type}.

  Your responsibilities:
  1. Analyze the task requirements and conversation history
  2. Determine if you need to use a tool or request user input
  3. If using a tool, provide the tool name and arguments
  4. If requesting input, provide a clear question to the user
  5. If the task is complete, summarize the result

  Available actions:
  - use_tool: Call a tool to perform an action
  - request_input: Ask the user for information
  - complete: Mark the task as done with a result

  Task context:
  Title: #{task.title}
  Description: #{task.description || "No description"}
  Current context: #{inspect(task.context)}
  """
end
```

### Available Tools

Configured in `Agent.available_tools/0`:

```elixir
[
  %{
    type: "function",
    function: %{
      name: "send_email",
      description: "Send an email message",
      parameters: %{
        type: "object",
        properties: %{
          to: %{type: "string"},
          subject: %{type: "string"},
          body: %{type: "string"}
        },
        required: ["to", "subject", "body"]
      }
    }
  },
  %{
    type: "function",
    function: %{
      name: "search_knowledge",
      description: "Search the user's knowledge base",
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string"}
        },
        required: ["query"]
      }
    }
  }
]
```

## Conversation Management

### Adding Messages

Messages track the full conversation history:

```elixir
# System message
Tasks.add_task_message(task.id, %{
  role: "system",
  content: "Task created"
})

# User message
Tasks.add_task_message(task.id, %{
  role: "user",
  content: "Schedule for tomorrow at 2pm"
})

# Agent message
Tasks.add_task_message(task.id, %{
  role: "agent",
  content: "I'll schedule the meeting for tomorrow at 2pm. Let me check availability..."
})

# Tool message
Tasks.add_task_message(task.id, %{
  role: "tool",
  content: "Tool executed successfully",
  metadata: %{
    "tool" => "send_email",
    "result" => %{"sent" => true}
  }
})
```

### Retrieving History

```elixir
# Get formatted conversation for LLM
conversation = Tasks.get_task_conversation(task.id)
# [
#   %{role: "system", content: "..."},
#   %{role: "user", content: "..."},
#   %{role: "agent", content: "..."}
# ]

# Get full messages with metadata
messages = Tasks.list_task_messages(task.id)
```

## User Interaction

### Handling User Input

When a task is waiting for input:

```elixir
# User submits input via UI
def handle_event("submit_input", %{"user_input" => input}, socket) do
  task = socket.assigns.task

  case TaskExecutorWorker.continue_after_input(task.id, input) do
    {:ok, _job} ->
      {:noreply, put_flash(socket, :info, "Input submitted")}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to submit")}
  end
end
```

**Worker Implementation**:
```elixir
def continue_after_input(task_id, user_input) do
  with {:ok, task} <- Tasks.get_task(task_id),
       {:ok, :continue} <- Agent.handle_user_input(task, user_input) do
    enqueue_task(task_id)
  end
end
```

**Agent Handler**:
```elixir
def handle_user_input(task, user_input) do
  if task.status == "waiting_for_input" do
    # Add user message
    Tasks.add_task_message(task.id, %{
      role: "user",
      content: user_input
    })

    # Resume task
    Tasks.update_task_status(task, "in_progress")
    {:ok, :continue}
  else
    {:error, :not_waiting_for_input}
  end
end
```

## Context Module

**Location**: `lib/financial_agent/tasks.ex`

### Key Functions

```elixir
# Create task
{:ok, task} = Tasks.create_task(%{...})

# Get task
task = Tasks.get_task(task_id)
task = Tasks.get_task_with_messages(task_id)

# Update status
{:ok, task} = Tasks.update_task_status(task, "completed", %{
  result: %{"success" => true}
})

# List tasks
tasks = Tasks.list_user_tasks(user_id)
tasks = Tasks.list_user_tasks_by_status(user_id, "in_progress")
tasks = Tasks.list_user_tasks_by_type(user_id, "schedule_meeting")

# Task messages
{:ok, message} = Tasks.add_task_message(task_id, %{...})
messages = Tasks.list_task_messages(task_id)
conversation = Tasks.get_task_conversation(task_id)

# Statistics
count = Tasks.count_tasks_by_status(user_id, "completed")
has_active = Tasks.has_active_tasks?(user_id)

# Cancel task
{:ok, task} = Tasks.cancel_task(task)

# Delete task
{:ok, task} = Tasks.delete_task(task)
```

## Worker Implementation

**Location**: `lib/financial_agent/workers/task_executor_worker.ex`

### Main Flow

```elixir
def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
  with {:ok, task} <- get_task(task_id),
       result <- Agent.execute_step(task) do
    handle_agent_result(task_id, result)
  end
end

defp handle_agent_result(task_id, {:ok, :completed, result}) do
  Logger.info("Task #{task_id} completed")
  :ok
end

defp handle_agent_result(task_id, {:ok, :waiting_for_input, message}) do
  Logger.info("Task #{task_id} waiting for input: #{message}")
  :ok
end

defp handle_agent_result(task_id, {:ok, :continue}) do
  Logger.info("Task #{task_id} continuing, re-enqueueing...")

  # Re-enqueue after 1 second
  %{"task_id" => task_id}
  |> __MODULE__.new(schedule_in: 1)
  |> Oban.insert()

  :ok
end
```

### Self-Enqueueing

For multi-step tasks, the worker re-enqueues itself:

```
Step 1: Agent decides to use tool
  ↓
Tool executes successfully
  ↓
Worker re-enqueues itself
  ↓
Step 2: Agent decides to request input
  ↓
Task pauses, waits for user
  ↓
User provides input
  ↓
Worker re-enqueued manually
  ↓
Step 3: Agent completes task
```

## UI Integration

### Tasks Index

**Route**: `/tasks`

**LiveView**: `TasksLive.Index`

Features:
- List all user tasks
- Filter by status (all/active/completed/failed)
- View task details
- Cancel active tasks

### Task Show

**Route**: `/tasks/:id`

**LiveView**: `TasksLive.Show`

Features:
- View full task details
- See conversation history
- Submit user input (if waiting)
- Retry failed tasks
- View results and errors

## Testing

### Unit Tests

**Test Context Functions**:
```elixir
test "creates task with valid attributes" do
  user = insert(:user)

  {:ok, task} = Tasks.create_task(%{
    user_id: user.id,
    title: "Test task",
    task_type: "custom"
  })

  assert task.title == "Test task"
  assert task.status == "pending"
end
```

**Test State Machine**:
```elixir
test "allows valid transition" do
  assert StateMachine.can_transition?("pending", "in_progress")
end

test "denies invalid transition" do
  refute StateMachine.can_transition?("completed", "pending")
end
```

### Integration Tests

**Test Full Workflow** (with mocks):
```elixir
@tag :integration
test "executes task to completion" do
  user = insert(:user)

  {:ok, task} = Tasks.create_task(%{
    user_id: user.id,
    title: "Test workflow",
    task_type: "custom"
  })

  # Mock LLM to return completion
  mock_llm_response(%{
    action: "complete",
    result: %{"success" => true}
  })

  # Execute
  assert {:ok, :completed, _} = Agent.execute_step(task)

  # Verify
  task = Tasks.get_task(task.id)
  assert task.status == "completed"
end
```

## Best Practices

### 1. Clear Titles and Descriptions

```elixir
# Good
%{
  title: "Schedule Q1 planning meeting",
  description: "Find a time that works for all engineering leads next week"
}

# Bad
%{
  title: "Task",
  description: ""
}
```

### 2. Meaningful Context

```elixir
# Good context
%{
  "participants" => ["alice@example.com", "bob@example.com"],
  "duration" => "60 minutes",
  "preferred_times" => ["afternoon", "morning"]
}

# Bad context
%{
  "data" => "some string"
}
```

### 3. Detailed Messages

```elixir
# Good message
"I've checked the calendars and found these available times:\n
- Monday 2pm-3pm\n
- Tuesday 10am-11am\n
Which works better?"

# Bad message
"Pick a time"
```

### 4. Handle Errors Gracefully

```elixir
case Agent.execute_step(task) do
  {:ok, result} ->
    handle_success(result)

  {:error, :invalid_transition} ->
    Logger.warning("Task #{task.id} in invalid state")
    :ok

  {:error, reason} ->
    Logger.error("Task failed: #{inspect(reason)}")
    Tasks.update_task_status(task, "failed", %{
      error: "Execution failed: #{inspect(reason)}"
    })
end
```

### 5. Idempotent Steps

Ensure steps can be safely retried:

```elixir
def execute_step(task) do
  # Check if already processed
  if task.status == "completed" do
    {:ok, :completed, task.result}
  else
    do_execute(task)
  end
end
```

## Monitoring

### Check Active Tasks

```elixir
# Count active tasks
Tasks.count_tasks_by_status(user_id, "in_progress")

# List stuck tasks (in progress > 1 hour)
one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

from(t in Task,
  where: t.status == "in_progress",
  where: t.updated_at < ^one_hour_ago
)
|> Repo.all()
```

### Monitor Worker Queue

```elixir
# Check tasks queue
Oban.check_queue(queue: :tasks)

# List pending jobs
from(j in Oban.Job,
  where: j.queue == "tasks" and j.state == "available"
)
|> Repo.all()
```

## Troubleshooting

### Task Stuck in "in_progress"

**Symptoms**: Task shows "in_progress" but no activity

**Possible Causes**:
1. Worker crashed
2. LLM API error
3. Tool execution failed

**Solutions**:
```elixir
# Check worker logs
Oban.check_queue(queue: :tasks)

# Manually retry
task = Tasks.get_task(task_id)
TaskExecutorWorker.enqueue_task(task.id)

# Or cancel if stuck
Tasks.cancel_task(task)
```

### Task Fails Repeatedly

**Check Logs**:
```elixir
# Find failed jobs
from(j in Oban.Job,
  where: j.worker == "TaskExecutorWorker",
  where: j.state in ["retryable", "discarded"],
  where: fragment("?->>'task_id' = ?", j.args, ^task_id)
)
|> Repo.all()
```

**Common Issues**:
- Invalid tool arguments
- Missing user credentials
- LLM API rate limits

## Related Documentation

- [Architecture Overview](./01-architecture-overview.md)
- [Oban Workers](./02-oban-workers.md)
- [Instructions System](./05-instructions-system.md)
- [Events & Tools](./06-events-and-tools.md)
