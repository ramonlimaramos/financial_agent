# Instructions System (Event-Driven Automation)

## Overview

The Instructions System enables users to create AI-powered automation rules in plain English. The system uses LLM-based evaluation to match events against user-defined conditions and automatically executes actions.

**Key Components:**
- **Instruction Schema**: User-defined automation rules
- **GmailMonitorWorker**: Polls Gmail API for new emails (cron)
- **EventProcessorWorker**: Processes events and matches against instructions
- **Matcher**: LLM-based condition evaluation with confidence scoring
- **Executor**: Action interpretation and tool execution
- **LiveView UI**: Real-time instruction management

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Gmail Monitor (Cron)                     │
│                  Runs every 2 minutes                        │
└──────────────────────┬──────────────────────────────────────┘
                       │ Detects new email
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                   EventProcessorWorker                       │
│          Enqueued with event data (email/contact)           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                        Matcher Module                        │
│         LLM evaluates event against instructions            │
│              Returns confidence score (0.0-1.0)             │
└──────────────────────┬──────────────────────────────────────┘
                       │ Confidence > 0.7?
                       ↓ YES
┌─────────────────────────────────────────────────────────────┐
│                       Executor Module                        │
│           LLM interprets action_text as JSON                │
│         Determines tools and parameters to execute          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                      ToolExecutor                            │
│        Executes tools (send_email, create_task, etc.)       │
│                   Returns result/error                       │
└─────────────────────────────────────────────────────────────┘
```

## Database Schema

### Instructions Table

```sql
CREATE TABLE instructions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  title VARCHAR(255) NOT NULL,
  trigger_type VARCHAR(50) NOT NULL,      -- 'new_email', 'new_contact', 'scheduled'
  condition_text TEXT NOT NULL,           -- Natural language condition
  action_text TEXT NOT NULL,              -- Natural language action
  is_active BOOLEAN DEFAULT true,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,

  UNIQUE(user_id, title)
);

CREATE INDEX instructions_user_id_index ON instructions(user_id);
CREATE INDEX instructions_trigger_type_index ON instructions(trigger_type);
CREATE INDEX instructions_is_active_index ON instructions(is_active);
```

**Schema**: `lib/financial_agent/instructions/instruction.ex`

```elixir
defmodule FinancialAgent.Instructions.Instruction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "instructions" do
    field :title, :string
    field :trigger_type, :string
    field :condition_text, :string
    field :action_text, :string
    field :is_active, :boolean, default: true

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:user_id, :title, :trigger_type, :condition_text, :action_text, :is_active])
    |> validate_required([:user_id, :title, :trigger_type, :condition_text, :action_text])
    |> validate_inclusion(:trigger_type, ["new_email", "new_contact", "scheduled"])
    |> unique_constraint([:user_id, :title])
  end
end
```

## Trigger Types

### 1. New Email (`new_email`)

**Monitoring**: GmailMonitorWorker polls Gmail API every 2 minutes

**Event Structure**:
```elixir
%{
  "type" => "email",
  "subject" => "Meeting tomorrow at 2pm",
  "from" => "alice@example.com",
  "to" => "bob@example.com",
  "content" => "Full email body text...",
  "metadata" => %{
    "message_id" => "msg_123",
    "thread_id" => "thread_456",
    "date" => "2024-01-15T10:30:00Z",
    "labels" => ["INBOX", "IMPORTANT"]
  }
}
```

**Example Instructions**:
- Condition: "Email mentions pricing or quote request"
- Action: "Send them our pricing document link"

### 2. New Contact (`new_contact`)

**Monitoring**: HubSpot webhook or periodic sync

**Event Structure**:
```elixir
%{
  "type" => "contact",
  "name" => "John Doe",
  "email" => "john@example.com",
  "company" => "Acme Inc",
  "metadata" => %{
    "contact_id" => "123",
    "lifecycle_stage" => "lead",
    "created_at" => "2024-01-15T10:30:00Z"
  }
}
```

**Example Instructions**:
- Condition: "New contact from enterprise company"
- Action: "Create task to send personalized welcome email"

### 3. Scheduled (`scheduled`)

**Monitoring**: Oban cron job (configurable interval)

**Event Structure**:
```elixir
%{
  "type" => "scheduled",
  "time" => "2024-01-15T09:00:00Z",
  "metadata" => %{
    "schedule" => "daily_9am"
  }
}
```

**Example Instructions**:
- Condition: "Every weekday at 9am"
- Action: "Send daily summary of new contacts"

## Matcher Module

**Location**: `lib/financial_agent/instructions/matcher.ex`

**Purpose**: Use LLM to evaluate if an event matches an instruction's condition

### Implementation

```elixir
defmodule FinancialAgent.Instructions.Matcher do
  @moduledoc """
  Uses LLM to match events against instruction conditions.
  """

  alias FinancialAgent.AI.LLMClient
  alias FinancialAgent.Instructions.Instruction

  @doc """
  Evaluates if an event matches an instruction's condition.

  Returns {:ok, confidence} where confidence is 0.0 to 1.0.
  Confidence > 0.7 is considered a match.
  """
  @spec match_event(Instruction.t(), map()) :: {:ok, float()} | {:error, term()}
  def match_event(%Instruction{} = instruction, event_data) do
    prompt = build_matcher_prompt(instruction, event_data)

    case LLMClient.chat_completion([
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]) do
      {:ok, response} ->
        parse_confidence(response)

      {:error, error} ->
        {:error, error}
    end
  end

  defp system_prompt do
    """
    You are an event matching system. Your job is to evaluate if an event matches a user's condition.

    You will be given:
    1. A condition in natural language (what the user wants to match)
    2. Event data (email, contact, etc.)

    Respond with ONLY a JSON object:
    {
      "matches": true/false,
      "confidence": 0.0-1.0,
      "reasoning": "Brief explanation of why it matches or not"
    }

    Confidence levels:
    - 0.9-1.0: Strong match, very confident
    - 0.7-0.89: Good match, confident
    - 0.5-0.69: Possible match, uncertain
    - 0.0-0.49: No match

    Be conservative. Only high confidence (>0.7) should trigger actions.
    """
  end

  defp build_matcher_prompt(instruction, event_data) do
    """
    Condition: #{instruction.condition_text}

    Event Type: #{event_data["type"]}

    Event Data:
    #{format_event_data(event_data)}

    Does this event match the condition? Provide your evaluation as JSON.
    """
  end

  defp format_event_data(event_data) do
    event_data
    |> Enum.map(fn {key, value} ->
      "- #{key}: #{inspect(value)}"
    end)
    |> Enum.join("\n")
  end

  defp parse_confidence(response) do
    case Jason.decode(response) do
      {:ok, %{"matches" => matches, "confidence" => confidence, "reasoning" => reasoning}} ->
        if matches and confidence > 0.7 do
          {:ok, %{confidence: confidence, reasoning: reasoning}}
        else
          {:ok, %{confidence: 0.0, reasoning: reasoning}}
        end

      {:error, _} ->
        {:error, :invalid_response}
    end
  end
end
```

### Confidence Scoring

**Thresholds**:
- **> 0.7**: Action triggered (high confidence match)
- **0.5-0.7**: Logged but not triggered (uncertain)
- **< 0.5**: Ignored (no match)

**Example Evaluations**:

```elixir
# Strong match (0.95)
Condition: "Email mentions pricing"
Email Subject: "What are your pricing tiers?"
→ High confidence, clear match

# Good match (0.8)
Condition: "Email from VIP customer"
Email From: "ceo@bigclient.com" (in VIP list)
→ Good confidence, matches criteria

# Uncertain (0.6)
Condition: "Email about urgent issue"
Email Subject: "Quick question"
→ Uncertain, "quick" might mean urgent but unclear

# No match (0.1)
Condition: "Email about pricing"
Email Subject: "Meeting notes from yesterday"
→ No match, completely different topic
```

## Executor Module

**Location**: `lib/financial_agent/instructions/executor.ex`

**Purpose**: Interpret action_text and execute appropriate tools

### Implementation

```elixir
defmodule FinancialAgent.Instructions.Executor do
  @moduledoc """
  Executes actions defined in instructions by interpreting natural language
  and calling appropriate tools.
  """

  alias FinancialAgent.AI.{LLMClient, ToolExecutor}
  alias FinancialAgent.Instructions.Instruction

  @doc """
  Executes an instruction's action given the matched event.

  Returns {:ok, result} or {:error, reason}.
  """
  @spec execute(Instruction.t(), map()) :: {:ok, map()} | {:error, term()}
  def execute(%Instruction{} = instruction, event_data) do
    prompt = build_executor_prompt(instruction, event_data)

    case LLMClient.chat_completion([
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]) do
      {:ok, response} ->
        parse_and_execute_action(response, event_data)

      {:error, error} ->
        {:error, error}
    end
  end

  defp system_prompt do
    """
    You are an action executor. Your job is to interpret a user's action description
    and convert it into a tool call.

    Available tools:
    1. send_email(to, subject, body)
    2. create_task(title, description, task_type)
    3. search_knowledge(query)
    4. update_contact(contact_id, fields)

    Respond with ONLY a JSON object:
    {
      "tool": "tool_name",
      "parameters": {
        "param1": "value1",
        "param2": "value2"
      },
      "reasoning": "Why you chose this tool and parameters"
    }

    Use the event data to fill in parameters intelligently.
    For example, if action is "Send them our pricing doc" and event has from email,
    use that email as the 'to' parameter.
    """
  end

  defp build_executor_prompt(instruction, event_data) do
    """
    Action to Execute: #{instruction.action_text}

    Event Data:
    #{format_event_data(event_data)}

    What tool should be called and with what parameters? Provide your answer as JSON.
    """
  end

  defp format_event_data(event_data) do
    event_data
    |> Enum.map(fn {key, value} -> "- #{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end

  defp parse_and_execute_action(response, event_data) do
    case Jason.decode(response) do
      {:ok, %{"tool" => tool, "parameters" => params, "reasoning" => reasoning}} ->
        Logger.info("Executing tool: #{tool} with params: #{inspect(params)}")
        Logger.info("Reasoning: #{reasoning}")

        ToolExecutor.execute_tool(tool, params, event_data)

      {:error, _} ->
        {:error, :invalid_action_format}
    end
  end
end
```

### Action Examples

**Example 1: Send Email**
```
Action Text: "Send them our pricing document"
Event: Email from alice@example.com asking about pricing

Executor Output:
{
  "tool": "send_email",
  "parameters": {
    "to": "alice@example.com",
    "subject": "Re: Pricing Information",
    "body": "Here's our pricing document: https://..."
  }
}
```

**Example 2: Create Task**
```
Action Text: "Create task to schedule follow-up call"
Event: New high-value contact created

Executor Output:
{
  "tool": "create_task",
  "parameters": {
    "title": "Schedule call with John Doe (Acme Inc)",
    "description": "Follow up with new contact about their needs",
    "task_type": "schedule_meeting"
  }
}
```

**Example 3: Search Knowledge**
```
Action Text: "Find relevant case studies and send them"
Event: Email asking about customer success stories

Executor Output:
{
  "tool": "search_knowledge",
  "parameters": {
    "query": "customer success stories case studies"
  }
}
```

## Event Processing Flow

### GmailMonitorWorker (Cron)

**Configuration**: `config/config.exs`

```elixir
config :financial_agent, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/2 * * * *", FinancialAgent.Workers.GmailMonitorWorker}
     ]}
  ]
```

**Process Flow**:

1. Cron triggers every 2 minutes
2. Fetch all users with active `new_email` instructions
3. For each user:
   - Get Google OAuth credential
   - Build Gmail API client
   - Query for emails after last check timestamp
   - For each new email:
     - Extract email data (subject, from, to, content)
     - Enqueue EventProcessorWorker with email event
4. Update last check timestamp

**Implementation**: `lib/financial_agent/workers/gmail_monitor_worker.ex`

```elixir
defmodule FinancialAgent.Workers.GmailMonitorWorker do
  use Oban.Worker,
    queue: :gmail_monitor,
    max_attempts: 3,
    priority: 2

  alias FinancialAgent.{Instructions, Accounts}
  alias FinancialAgent.Clients.GmailClient
  alias FinancialAgent.Workers.EventProcessorWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    last_check = Map.get(args, "last_check", unix_time_24h_ago())

    # Get users with active email instructions
    user_ids = Instructions.list_users_with_active_email_instructions()

    Enum.each(user_ids, fn user_id ->
      process_user_emails(user_id, last_check)
    end)

    :ok
  end

  defp process_user_emails(user_id, last_check) do
    with {:ok, credential} <- Accounts.get_google_credential(user_id),
         {:ok, client} <- GmailClient.build_client(credential),
         {:ok, messages} <- GmailClient.list_messages(client, after: last_check) do

      Enum.each(messages, fn message ->
        event_data = %{
          "type" => "email",
          "subject" => message["subject"],
          "from" => message["from"],
          "to" => message["to"],
          "content" => message["body"],
          "metadata" => %{
            "message_id" => message["id"],
            "thread_id" => message["threadId"],
            "date" => message["date"],
            "labels" => message["labelIds"]
          }
        }

        %{
          "user_id" => user_id,
          "event_type" => "email",
          "event_data" => event_data
        }
        |> EventProcessorWorker.new()
        |> Oban.insert()
      end)
    else
      {:error, reason} ->
        Logger.error("Failed to process emails for user #{user_id}: #{inspect(reason)}")
    end
  end

  defp unix_time_24h_ago do
    DateTime.utc_now()
    |> DateTime.add(-24 * 60 * 60, :second)
    |> DateTime.to_unix()
  end
end
```

### EventProcessorWorker

**Purpose**: Process individual events and match against instructions

**Configuration**: `lib/financial_agent/workers/event_processor_worker.ex`

```elixir
defmodule FinancialAgent.Workers.EventProcessorWorker do
  use Oban.Worker,
    queue: :events,
    max_attempts: 3,
    priority: 1

  alias FinancialAgent.Instructions
  alias FinancialAgent.Instructions.{Matcher, Executor}
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "event_type" => event_type, "event_data" => event_data}}) do
    Logger.info("Processing #{event_type} event for user #{user_id}")

    # Get active instructions for this trigger type
    trigger_type = event_type_to_trigger_type(event_type)
    instructions = Instructions.list_active_instructions_by_trigger(user_id, trigger_type)

    Logger.info("Found #{length(instructions)} active instructions")

    # Evaluate each instruction
    Enum.each(instructions, fn instruction ->
      case Matcher.match_event(instruction, event_data) do
        {:ok, %{confidence: confidence, reasoning: reasoning}} when confidence > 0.7 ->
          Logger.info("Instruction '#{instruction.title}' matched with confidence #{confidence}")
          Logger.info("Reasoning: #{reasoning}")

          # Execute the action
          case Executor.execute(instruction, event_data) do
            {:ok, result} ->
              Logger.info("Action executed successfully: #{inspect(result)}")

            {:error, error} ->
              Logger.error("Failed to execute action: #{inspect(error)}")
          end

        {:ok, %{confidence: confidence, reasoning: reasoning}} ->
          Logger.debug("Instruction '#{instruction.title}' did not match (confidence: #{confidence})")
          Logger.debug("Reasoning: #{reasoning}")

        {:error, error} ->
          Logger.error("Error matching instruction: #{inspect(error)}")
      end
    end)

    :ok
  end

  defp event_type_to_trigger_type("email"), do: "new_email"
  defp event_type_to_trigger_type("contact"), do: "new_contact"
  defp event_type_to_trigger_type(_), do: "scheduled"
end
```

## LiveView UI Integration

### Index Page

**Location**: `lib/financial_agent_web/live/instructions_live/index.ex`

**Features**:
- List all user instructions
- Create new instruction (modal)
- Edit existing instruction (modal)
- Toggle active/inactive
- Delete instruction with confirmation
- Stream-based real-time updates

**Key Functions**:

```elixir
@impl true
def mount(_params, session, socket) do
  user_id = get_user_id(session)

  {:ok,
   socket
   |> assign(:user_id, user_id)
   |> assign(:page_title, "Instructions")
   |> stream(:instructions, Instructions.list_instructions(user_id))}
end

@impl true
def handle_event("toggle_active", %{"id" => id}, socket) do
  instruction = Instructions.get_instruction!(id)

  case Instructions.update_instruction(instruction, %{is_active: !instruction.is_active}) do
    {:ok, updated_instruction} ->
      {:noreply, stream_insert(socket, :instructions, updated_instruction)}

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to update instruction")}
  end
end

@impl true
def handle_event("delete", %{"id" => id}, socket) do
  instruction = Instructions.get_instruction!(id)

  case Instructions.delete_instruction(instruction) do
    {:ok, _} ->
      {:noreply, stream_delete(socket, :instructions, instruction)}

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to delete instruction")}
  end
end
```

### Form Component

**Location**: `lib/financial_agent_web/live/instructions_live/form_component.ex`

**Features**:
- Modal form for create/edit
- Dropdown for trigger type selection
- Text inputs for title
- Textarea for condition and action
- Real-time validation
- Flash messages on success/error

**Key Functions**:

```elixir
@impl true
def handle_event("save", %{"instruction" => instruction_params}, socket) do
  save_instruction(socket, socket.assigns.action, instruction_params)
end

defp save_instruction(socket, :new, instruction_params) do
  instruction_params = Map.put(instruction_params, "user_id", socket.assigns.user_id)

  case Instructions.create_instruction(instruction_params) do
    {:ok, instruction} ->
      notify_parent({:saved, instruction})

      {:noreply,
       socket
       |> put_flash(:info, "Instruction created successfully")
       |> push_patch(to: socket.assigns.patch)}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign_form(socket, changeset)}
  end
end

defp save_instruction(socket, :edit, instruction_params) do
  case Instructions.update_instruction(socket.assigns.instruction, instruction_params) do
    {:ok, instruction} ->
      notify_parent({:saved, instruction})

      {:noreply,
       socket
       |> put_flash(:info, "Instruction updated successfully")
       |> push_patch(to: socket.assigns.patch)}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign_form(socket, changeset)}
  end
end
```

## Configuration

### Environment Variables

```bash
# Gmail monitoring interval (in minutes)
GMAIL_MONITOR_INTERVAL=2

# OpenAI configuration (for Matcher and Executor)
OPENAI_API_KEY=sk-...
OPENAI_CHAT_MODEL=gpt-4o
```

### Runtime Configuration

**Location**: `config/runtime.exs`

```elixir
config :financial_agent,
  gmail_monitor_interval: System.get_env("GMAIL_MONITOR_INTERVAL", "2") |> String.to_integer()

config :financial_agent, :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  chat_model: System.get_env("OPENAI_CHAT_MODEL", "gpt-4o"),
  embedding_model: System.get_env("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
```

## Testing

### Unit Tests

**Test Instruction Schema**:

```elixir
defmodule FinancialAgent.Instructions.InstructionTest do
  use FinancialAgent.DataCase

  alias FinancialAgent.Instructions.Instruction

  describe "changeset/2" do
    test "valid attributes" do
      user = insert(:user)

      changeset = Instruction.changeset(%Instruction{}, %{
        user_id: user.id,
        title: "Pricing emails",
        trigger_type: "new_email",
        condition_text: "Email mentions pricing",
        action_text: "Send pricing document"
      })

      assert changeset.valid?
    end

    test "requires trigger_type to be valid" do
      changeset = Instruction.changeset(%Instruction{}, %{
        trigger_type: "invalid"
      })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).trigger_type
    end
  end
end
```

**Test Matcher Module**:

```elixir
defmodule FinancialAgent.Instructions.MatcherTest do
  use FinancialAgent.DataCase
  import Mox

  alias FinancialAgent.Instructions.Matcher

  setup :verify_on_exit!

  test "matches email about pricing with high confidence" do
    instruction = insert(:instruction,
      condition_text: "Email mentions pricing or quotes"
    )

    event_data = %{
      "type" => "email",
      "subject" => "What are your pricing tiers?",
      "from" => "customer@example.com",
      "content" => "I'm interested in your pricing..."
    }

    # Mock LLM response
    expect(LLMClientMock, :chat_completion, fn _messages ->
      {:ok, ~s({"matches": true, "confidence": 0.95, "reasoning": "Email explicitly asks about pricing"})}
    end)

    assert {:ok, %{confidence: confidence}} = Matcher.match_event(instruction, event_data)
    assert confidence > 0.7
  end
end
```

**Test Executor Module**:

```elixir
defmodule FinancialAgent.Instructions.ExecutorTest do
  use FinancialAgent.DataCase
  import Mox

  alias FinancialAgent.Instructions.Executor

  setup :verify_on_exit!

  test "executes send_email action" do
    instruction = insert(:instruction,
      action_text: "Send them our pricing document"
    )

    event_data = %{
      "type" => "email",
      "from" => "customer@example.com",
      "subject" => "Pricing inquiry"
    }

    # Mock LLM response
    expect(LLMClientMock, :chat_completion, fn _messages ->
      {:ok, ~s({
        "tool": "send_email",
        "parameters": {
          "to": "customer@example.com",
          "subject": "Re: Pricing Information",
          "body": "Here's our pricing: ..."
        },
        "reasoning": "Customer asked about pricing"
      })}
    end)

    # Mock tool execution
    expect(ToolExecutorMock, :execute_tool, fn "send_email", params, _event ->
      assert params["to"] == "customer@example.com"
      {:ok, %{message_id: "msg_123"}}
    end)

    assert {:ok, _result} = Executor.execute(instruction, event_data)
  end
end
```

### Integration Tests

**Test Full Event Processing**:

```elixir
@tag :integration
test "processes email event end-to-end" do
  user = insert(:user)

  # Create instruction
  instruction = insert(:instruction,
    user: user,
    trigger_type: "new_email",
    condition_text: "Email about pricing",
    action_text: "Create task to respond",
    is_active: true
  )

  # Simulate email event
  event_data = %{
    "type" => "email",
    "subject" => "Pricing question",
    "from" => "customer@example.com",
    "content" => "What are your prices?"
  }

  # Enqueue event processor
  %{
    "user_id" => user.id,
    "event_type" => "email",
    "event_data" => event_data
  }
  |> EventProcessorWorker.new()
  |> Oban.insert!()

  # Drain queue
  assert :ok = Oban.drain_queue(queue: :events)

  # Verify task was created
  assert Repo.aggregate(Task, :count) == 1
  task = Repo.one(Task)
  assert task.user_id == user.id
  assert task.title =~ "respond"
end
```

## Best Practices

### 1. Writing Effective Conditions

**Good Conditions**:
- ✅ "Email mentions pricing, quotes, or costs"
- ✅ "Email from VIP customer (fortune500.com domain)"
- ✅ "Contact works at enterprise company (> 1000 employees)"

**Bad Conditions**:
- ❌ "Important email" (too vague)
- ❌ "Email I should respond to" (subjective)
- ❌ "Urgent" (hard to determine without context)

### 2. Writing Clear Actions

**Good Actions**:
- ✅ "Send them our pricing PDF from the knowledge base"
- ✅ "Create task to schedule 30-minute intro call"
- ✅ "Search knowledge base for case studies and send top 3 results"

**Bad Actions**:
- ❌ "Handle it" (unclear what to do)
- ❌ "Respond appropriately" (too vague)
- ❌ "Do the needful" (not actionable)

### 3. Confidence Threshold Tuning

Adjust confidence threshold based on action criticality:

```elixir
# High-stakes actions (sending email to customer)
confidence_threshold = 0.8

# Low-stakes actions (creating internal task)
confidence_threshold = 0.6

# Destructive actions (deleting data)
confidence_threshold = 0.95
```

### 4. Rate Limiting

Monitor Gmail API usage to avoid rate limits:

```elixir
# Adjust polling interval if hitting limits
config :financial_agent,
  gmail_monitor_interval: 5  # Increase from 2 to 5 minutes
```

### 5. Error Handling

Always handle LLM errors gracefully:

```elixir
case Matcher.match_event(instruction, event_data) do
  {:ok, result} ->
    # Process result

  {:error, :timeout} ->
    # Retry with backoff

  {:error, :invalid_response} ->
    # Log and skip
    Logger.error("Invalid LLM response for instruction #{instruction.id}")
end
```

## Monitoring & Debugging

### Check Active Instructions

```elixir
# In IEx
alias FinancialAgent.Instructions

# List all active instructions
Instructions.list_active_instructions(user_id)

# Count by trigger type
Instructions.count_active_instructions_by_trigger(user_id, "new_email")
```

### Monitor Event Processing

```elixir
# Check events queue
Oban.check_queue(queue: :events)

# List recent event jobs
from(j in Oban.Job,
  where: j.worker == "EventProcessorWorker",
  where: j.inserted_at > ago(1, "hour"),
  order_by: [desc: j.inserted_at],
  limit: 10
)
|> Repo.all()
```

### Debug Matcher/Executor

Enable debug logging:

```elixir
# In config/dev.exs
config :logger, level: :debug

# Or runtime
Logger.configure(level: :debug)
```

Check logs for matcher confidence scores:

```
[info] Processing email event for user abc-123
[info] Found 3 active instructions
[info] Instruction 'Pricing emails' matched with confidence 0.85
[info] Reasoning: Email explicitly asks about pricing tiers
[info] Executing tool: send_email with params: %{to: "customer@example.com", ...}
[info] Action executed successfully
```

## Troubleshooting

### Instructions Not Triggering

**Possible Causes**:
1. Instruction is inactive (`is_active: false`)
2. Confidence threshold not met (< 0.7)
3. GmailMonitorWorker not running
4. Event not matching trigger type

**Solutions**:

```elixir
# Check instruction status
instruction = Instructions.get_instruction!(id)
IO.inspect(instruction.is_active)

# Check cron job
Oban.check_queue(queue: :gmail_monitor)

# Manually test matcher
Matcher.match_event(instruction, test_event_data)
```

### Low Confidence Scores

**Causes**:
- Condition text too vague
- Event data insufficient
- LLM model not understanding intent

**Solutions**:
- Rewrite condition with more specific keywords
- Add examples to condition text
- Use GPT-4o instead of GPT-3.5

### Action Not Executing

**Causes**:
- Invalid action text format
- Tool not available
- Missing parameters

**Solutions**:

```elixir
# Test executor directly
Executor.execute(instruction, event_data)

# Check tool executor logs
Logger.debug("Available tools: #{inspect(ToolExecutor.list_tools())}")
```

## Performance Optimization

### Reduce LLM Calls

Cache common evaluations:

```elixir
defmodule Matcher do
  @cache_ttl 5 * 60 * 1000  # 5 minutes

  def match_event(instruction, event_data) do
    cache_key = {instruction.id, event_hash(event_data)}

    case Cachex.get(:matcher_cache, cache_key) do
      {:ok, nil} ->
        result = do_match_event(instruction, event_data)
        Cachex.put(:matcher_cache, cache_key, result, ttl: @cache_ttl)
        result

      {:ok, cached_result} ->
        cached_result
    end
  end
end
```

### Batch Event Processing

Process multiple events per job:

```elixir
def perform(%Oban.Job{args: %{"event_ids" => event_ids}}) do
  Enum.each(event_ids, &process_event/1)
end
```

### Optimize Gmail Polling

Only fetch new messages:

```elixir
# Store last message ID
last_message_id = get_last_processed_message_id(user_id)

GmailClient.list_messages(client,
  after: last_check,
  max_results: 50
)
```

## Related Documentation

- [Architecture Overview](./01-architecture-overview.md)
- [Oban Workers](./02-oban-workers.md)
- [Tasks System](./04-tasks-system.md)
- [Events & Tools](./06-events-and-tools.md)
