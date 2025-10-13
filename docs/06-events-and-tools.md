# Events and Tools

## Overview

The Events and Tools system provides the runtime environment for instruction execution and task automation. Events represent external triggers (emails, contacts, scheduled time), while Tools are executable functions that the AI can call to perform actions.

**Key Components:**
- **Event System**: Structured representation of external triggers
- **Tool Registry**: Catalog of available tools with metadata
- **ToolExecutor**: Dynamic tool invocation engine
- **Tool Definitions**: Individual tool implementations

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Event Sources                         │
│        Gmail API, HubSpot API, Calendar, Webhooks           │
└──────────────────────┬──────────────────────────────────────┘
                       │ Events
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                    EventProcessorWorker                      │
│              Matcher → Executor → ToolExecutor              │
└──────────────────────┬──────────────────────────────────────┘
                       │ Tool Invocation
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                       Tool Registry                          │
│     send_email, create_task, search_knowledge, etc.         │
└──────────────────────┬──────────────────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ↓               ↓               ↓
┌──────────┐    ┌──────────┐    ┌──────────┐
│  Email   │    │  Tasks   │    │   RAG    │
│  Service │    │  System  │    │ Retrieval│
└──────────┘    └──────────┘    └──────────┘
```

## Event System

### Event Structure

All events follow a standard structure:

```elixir
%{
  "type" => "email" | "contact" | "scheduled",
  # Type-specific fields
  "metadata" => %{
    # Additional context
  }
}
```

### Event Types

#### 1. Email Event

**Source**: Gmail API via GmailMonitorWorker

**Structure**:
```elixir
%{
  "type" => "email",
  "subject" => "Meeting request",
  "from" => "alice@example.com",
  "to" => "bob@example.com",
  "content" => "Full email body...",
  "metadata" => %{
    "message_id" => "msg_abc123",
    "thread_id" => "thread_xyz789",
    "date" => "2024-01-15T10:30:00Z",
    "labels" => ["INBOX", "IMPORTANT"],
    "has_attachments" => false,
    "cc" => ["charlie@example.com"],
    "bcc" => []
  }
}
```

**Example Creation**:
```elixir
defmodule GmailMonitorWorker do
  defp build_email_event(message) do
    %{
      "type" => "email",
      "subject" => get_header(message, "Subject"),
      "from" => get_header(message, "From"),
      "to" => get_header(message, "To"),
      "content" => extract_body(message),
      "metadata" => %{
        "message_id" => message["id"],
        "thread_id" => message["threadId"],
        "date" => get_header(message, "Date"),
        "labels" => message["labelIds"] || [],
        "has_attachments" => has_attachments?(message)
      }
    }
  end
end
```

#### 2. Contact Event

**Source**: HubSpot API via HubspotSyncWorker or webhooks

**Structure**:
```elixir
%{
  "type" => "contact",
  "name" => "John Doe",
  "email" => "john@example.com",
  "company" => "Acme Inc",
  "phone" => "+1-555-0123",
  "metadata" => %{
    "contact_id" => "123456",
    "lifecycle_stage" => "lead",
    "lead_status" => "new",
    "created_at" => "2024-01-15T10:30:00Z",
    "company_size" => "1000-5000",
    "industry" => "Technology",
    "website" => "https://acme.com"
  }
}
```

**Example Creation**:
```elixir
defmodule HubspotSyncWorker do
  defp build_contact_event(contact_data) do
    properties = contact_data["properties"]

    %{
      "type" => "contact",
      "name" => "#{properties["firstname"]} #{properties["lastname"]}",
      "email" => properties["email"],
      "company" => properties["company"],
      "phone" => properties["phone"],
      "metadata" => %{
        "contact_id" => contact_data["id"],
        "lifecycle_stage" => properties["lifecyclestage"],
        "lead_status" => properties["hs_lead_status"],
        "created_at" => contact_data["createdAt"],
        "company_size" => properties["company_size"],
        "industry" => properties["industry"]
      }
    }
  end
end
```

#### 3. Scheduled Event

**Source**: Oban cron jobs or user-defined schedules

**Structure**:
```elixir
%{
  "type" => "scheduled",
  "schedule_name" => "daily_summary",
  "time" => "2024-01-15T09:00:00Z",
  "metadata" => %{
    "schedule_id" => "sched_123",
    "recurrence" => "daily",
    "timezone" => "America/New_York",
    "parameters" => %{
      "summary_type" => "contacts",
      "time_range" => "24h"
    }
  }
}
```

**Example Creation**:
```elixir
defmodule ScheduledEventsWorker do
  defp build_scheduled_event(schedule) do
    %{
      "type" => "scheduled",
      "schedule_name" => schedule.name,
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "metadata" => %{
        "schedule_id" => schedule.id,
        "recurrence" => schedule.recurrence,
        "timezone" => schedule.timezone,
        "parameters" => schedule.parameters || %{}
      }
    }
  end
end
```

### Event Validation

Events should be validated before processing:

```elixir
defmodule FinancialAgent.Events.Validator do
  @doc """
  Validates event structure and required fields.
  """
  @spec validate_event(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_event(%{"type" => type} = event) when type in ["email", "contact", "scheduled"] do
    case validate_type_specific_fields(event) do
      :ok -> {:ok, event}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_event(_), do: {:error, "Invalid event type or missing type field"}

  defp validate_type_specific_fields(%{"type" => "email"} = event) do
    required = ["subject", "from", "content"]
    validate_required_fields(event, required)
  end

  defp validate_type_specific_fields(%{"type" => "contact"} = event) do
    required = ["name", "email"]
    validate_required_fields(event, required)
  end

  defp validate_type_specific_fields(%{"type" => "scheduled"} = event) do
    required = ["schedule_name", "time"]
    validate_required_fields(event, required)
  end

  defp validate_required_fields(event, required) do
    missing = Enum.reject(required, &Map.has_key?(event, &1))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end
end
```

## Tool System

### Tool Registry

**Location**: `lib/financial_agent/ai/tool_registry.ex`

**Purpose**: Central catalog of all available tools with metadata

```elixir
defmodule FinancialAgent.AI.ToolRegistry do
  @moduledoc """
  Registry of all available tools that can be called by the AI.
  """

  @tools %{
    "send_email" => %{
      name: "send_email",
      description: "Send an email to a recipient",
      parameters: [
        %{name: "to", type: "string", required: true, description: "Recipient email address"},
        %{name: "subject", type: "string", required: true, description: "Email subject"},
        %{name: "body", type: "string", required: true, description: "Email body content"},
        %{name: "cc", type: "array", required: false, description: "CC recipients"},
        %{name: "attachments", type: "array", required: false, description: "File attachments"}
      ],
      examples: [
        %{
          parameters: %{
            "to" => "customer@example.com",
            "subject" => "Re: Your inquiry",
            "body" => "Thank you for your message..."
          }
        }
      ]
    },

    "create_task" => %{
      name: "create_task",
      description: "Create a new task for the user",
      parameters: [
        %{name: "title", type: "string", required: true, description: "Task title"},
        %{name: "description", type: "string", required: true, description: "Task description"},
        %{name: "task_type", type: "string", required: true, description: "Type: schedule_meeting, compose_email, research, data_analysis, custom"}
      ],
      examples: [
        %{
          parameters: %{
            "title" => "Schedule call with John Doe",
            "description" => "Follow up on pricing discussion",
            "task_type" => "schedule_meeting"
          }
        }
      ]
    },

    "search_knowledge" => %{
      name: "search_knowledge",
      description: "Search the knowledge base (Gmail and HubSpot data) using semantic search",
      parameters: [
        %{name: "query", type: "string", required: true, description: "Search query"},
        %{name: "limit", type: "integer", required: false, description: "Max results (default: 5)"},
        %{name: "source", type: "string", required: false, description: "Filter by source: gmail, hubspot, or all"}
      ],
      examples: [
        %{
          parameters: %{
            "query" => "pricing discussions with enterprise customers",
            "limit" => 5,
            "source" => "gmail"
          }
        }
      ]
    },

    "update_contact" => %{
      name: "update_contact",
      description: "Update a HubSpot contact's properties",
      parameters: [
        %{name: "contact_id", type: "string", required: true, description: "HubSpot contact ID"},
        %{name: "properties", type: "object", required: true, description: "Properties to update"}
      ],
      examples: [
        %{
          parameters: %{
            "contact_id" => "123456",
            "properties" => %{
              "lifecyclestage" => "opportunity",
              "hs_lead_status" => "qualified"
            }
          }
        }
      ]
    },

    "search_contacts" => %{
      name: "search_contacts",
      description: "Search HubSpot contacts by criteria",
      parameters: [
        %{name: "query", type: "string", required: false, description: "Search query"},
        %{name: "filters", type: "object", required: false, description: "Property filters"}
      ],
      examples: [
        %{
          parameters: %{
            "filters" => %{
              "lifecyclestage" => "lead",
              "company_size" => "enterprise"
            }
          }
        }
      ]
    },

    "schedule_meeting" => %{
      name: "schedule_meeting",
      description: "Create a calendar event",
      parameters: [
        %{name: "title", type: "string", required: true, description: "Meeting title"},
        %{name: "attendees", type: "array", required: true, description: "List of attendee emails"},
        %{name: "start_time", type: "string", required: true, description: "ISO 8601 datetime"},
        %{name: "duration_minutes", type: "integer", required: true, description: "Meeting duration"},
        %{name: "description", type: "string", required: false, description: "Meeting description"}
      ],
      examples: [
        %{
          parameters: %{
            "title" => "Product Demo",
            "attendees" => ["customer@example.com"],
            "start_time" => "2024-01-20T14:00:00Z",
            "duration_minutes" => 30
          }
        }
      ]
    }
  }

  @doc """
  List all available tools.
  """
  @spec list_tools() :: list(map())
  def list_tools do
    Map.values(@tools)
  end

  @doc """
  Get a specific tool by name.
  """
  @spec get_tool(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_tool(name) do
    case Map.fetch(@tools, name) do
      {:ok, tool} -> {:ok, tool}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Check if a tool exists.
  """
  @spec tool_exists?(String.t()) :: boolean()
  def tool_exists?(name), do: Map.has_key?(@tools, name)

  @doc """
  Get tool definitions formatted for LLM.
  """
  @spec get_tool_definitions() :: list(map())
  def get_tool_definitions do
    Enum.map(@tools, fn {_name, tool} ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: format_parameters(tool.parameters)
      }
    end)
  end

  defp format_parameters(parameters) do
    required = Enum.filter(parameters, & &1.required) |> Enum.map(& &1.name)

    properties =
      Enum.into(parameters, %{}, fn param ->
        {param.name, %{
          type: param.type,
          description: param.description
        }}
      end)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end
end
```

### ToolExecutor

**Location**: `lib/financial_agent/ai/tool_executor.ex`

**Purpose**: Dynamically invoke tools based on name and parameters

```elixir
defmodule FinancialAgent.AI.ToolExecutor do
  @moduledoc """
  Executes tools by name with given parameters.
  """

  require Logger
  alias FinancialAgent.AI.{Tools, ToolRegistry}

  @doc """
  Execute a tool by name with parameters.

  Returns {:ok, result} or {:error, reason}.
  """
  @spec execute_tool(String.t(), map(), map()) :: {:ok, any()} | {:error, term()}
  def execute_tool(tool_name, parameters, context \\ %{}) do
    Logger.info("Executing tool: #{tool_name}")
    Logger.debug("Parameters: #{inspect(parameters)}")
    Logger.debug("Context: #{inspect(context)}")

    with {:ok, _tool_def} <- ToolRegistry.get_tool(tool_name),
         {:ok, validated_params} <- validate_parameters(tool_name, parameters),
         {:ok, result} <- dispatch_tool(tool_name, validated_params, context) do
      Logger.info("Tool executed successfully: #{tool_name}")
      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("Tool execution failed: #{tool_name} - #{inspect(reason)}")
        error
    end
  end

  defp validate_parameters(tool_name, parameters) do
    case ToolRegistry.get_tool(tool_name) do
      {:ok, tool_def} ->
        required_params = Enum.filter(tool_def.parameters, & &1.required) |> Enum.map(& &1.name)
        missing = Enum.reject(required_params, &Map.has_key?(parameters, &1))

        if Enum.empty?(missing) do
          {:ok, parameters}
        else
          {:error, "Missing required parameters: #{Enum.join(missing, ", ")}"}
        end

      {:error, :not_found} ->
        {:error, :tool_not_found}
    end
  end

  defp dispatch_tool("send_email", params, context) do
    Tools.SendEmail.execute(params, context)
  end

  defp dispatch_tool("create_task", params, context) do
    Tools.CreateTask.execute(params, context)
  end

  defp dispatch_tool("search_knowledge", params, context) do
    Tools.SearchKnowledge.execute(params, context)
  end

  defp dispatch_tool("update_contact", params, context) do
    Tools.UpdateContact.execute(params, context)
  end

  defp dispatch_tool("search_contacts", params, context) do
    Tools.SearchContacts.execute(params, context)
  end

  defp dispatch_tool("schedule_meeting", params, context) do
    Tools.ScheduleMeeting.execute(params, context)
  end

  defp dispatch_tool(tool_name, _params, _context) do
    {:error, "Tool not implemented: #{tool_name}"}
  end
end
```

### Tool Implementations

#### 1. SendEmail Tool

**Location**: `lib/financial_agent/ai/tools/send_email.ex`

```elixir
defmodule FinancialAgent.AI.Tools.SendEmail do
  @moduledoc """
  Tool for sending emails via Gmail API.
  """

  require Logger
  alias FinancialAgent.{Accounts, Clients.GmailClient}

  @doc """
  Send an email.

  ## Parameters
    - to: Recipient email address
    - subject: Email subject
    - body: Email body (plain text or HTML)
    - cc: CC recipients (optional)
    - attachments: File attachments (optional)

  ## Context
    - user_id: User sending the email
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)

    with {:ok, credential} <- Accounts.get_google_credential(user_id),
         {:ok, client} <- GmailClient.build_client(credential),
         {:ok, message} <- build_message(params),
         {:ok, result} <- GmailClient.send_message(client, message) do

      Logger.info("Email sent successfully to #{params["to"]}")

      {:ok, %{
        message_id: result["id"],
        thread_id: result["threadId"],
        to: params["to"],
        subject: params["subject"]
      }}
    else
      {:error, reason} = error ->
        Logger.error("Failed to send email: #{inspect(reason)}")
        error
    end
  end

  defp build_message(params) do
    to = params["to"]
    subject = params["subject"]
    body = params["body"]
    cc = params["cc"] || []

    # Build RFC 2822 message
    message = """
    To: #{to}
    Subject: #{subject}
    #{if cc != [], do: "Cc: #{Enum.join(cc, ", ")}\n", else: ""}
    Content-Type: text/plain; charset=utf-8

    #{body}
    """

    {:ok, message}
  end
end
```

#### 2. CreateTask Tool

**Location**: `lib/financial_agent/ai/tools/create_task.ex`

```elixir
defmodule FinancialAgent.AI.Tools.CreateTask do
  @moduledoc """
  Tool for creating tasks in the task system.
  """

  require Logger
  alias FinancialAgent.Tasks

  @doc """
  Create a new task.

  ## Parameters
    - title: Task title
    - description: Task description
    - task_type: Type of task (schedule_meeting, compose_email, research, etc.)

  ## Context
    - user_id: User who owns the task
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)

    task_params = %{
      user_id: user_id,
      title: params["title"],
      description: params["description"],
      task_type: params["task_type"]
    }

    case Tasks.create_task(task_params) do
      {:ok, task} ->
        Logger.info("Task created: #{task.id} - #{task.title}")

        {:ok, %{
          task_id: task.id,
          title: task.title,
          status: task.status
        }}

      {:error, changeset} ->
        Logger.error("Failed to create task: #{inspect(changeset.errors)}")
        {:error, :task_creation_failed}
    end
  end
end
```

#### 3. SearchKnowledge Tool

**Location**: `lib/financial_agent/ai/tools/search_knowledge.ex`

```elixir
defmodule FinancialAgent.AI.Tools.SearchKnowledge do
  @moduledoc """
  Tool for searching the knowledge base using RAG.
  """

  require Logger
  alias FinancialAgent.RAG.Retrieval

  @doc """
  Search the knowledge base.

  ## Parameters
    - query: Search query
    - limit: Maximum number of results (default: 5)
    - source: Filter by source (gmail, hubspot, all)

  ## Context
    - user_id: User performing the search
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)
    query = params["query"]
    limit = params["limit"] || 5
    source = params["source"]

    opts = [limit: limit]
    opts = if source, do: Keyword.put(opts, :source, source), else: opts

    case Retrieval.search_similar_chunks(user_id, query, opts) do
      {:ok, results} ->
        Logger.info("Found #{length(results)} results for query: #{query}")

        formatted_results = Enum.map(results, fn %{chunk: chunk, similarity: sim} ->
          %{
            content: chunk.content,
            source: chunk.source,
            similarity: Float.round(sim, 2),
            metadata: chunk.metadata
          }
        end)

        {:ok, %{
          query: query,
          results: formatted_results,
          count: length(results)
        }}

      {:error, reason} ->
        Logger.error("Knowledge search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

#### 4. UpdateContact Tool

**Location**: `lib/financial_agent/ai/tools/update_contact.ex`

```elixir
defmodule FinancialAgent.AI.Tools.UpdateContact do
  @moduledoc """
  Tool for updating HubSpot contacts.
  """

  require Logger
  alias FinancialAgent.{Accounts, Clients.HubspotClient}

  @doc """
  Update a HubSpot contact.

  ## Parameters
    - contact_id: HubSpot contact ID
    - properties: Map of properties to update

  ## Context
    - user_id: User performing the update
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)
    contact_id = params["contact_id"]
    properties = params["properties"]

    with {:ok, credential} <- Accounts.get_hubspot_credential(user_id),
         {:ok, client} <- HubspotClient.build_client(credential),
         {:ok, result} <- HubspotClient.update_contact(client, contact_id, properties) do

      Logger.info("Updated contact #{contact_id}")

      {:ok, %{
        contact_id: contact_id,
        updated_properties: Map.keys(properties)
      }}
    else
      {:error, reason} = error ->
        Logger.error("Failed to update contact: #{inspect(reason)}")
        error
    end
  end
end
```

#### 5. SearchContacts Tool

**Location**: `lib/financial_agent/ai/tools/search_contacts.ex`

```elixir
defmodule FinancialAgent.AI.Tools.SearchContacts do
  @moduledoc """
  Tool for searching HubSpot contacts.
  """

  require Logger
  alias FinancialAgent.{Accounts, Clients.HubspotClient}

  @doc """
  Search HubSpot contacts.

  ## Parameters
    - query: Text search query (optional)
    - filters: Property filters (optional)

  ## Context
    - user_id: User performing the search
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)
    query = params["query"]
    filters = params["filters"] || %{}

    with {:ok, credential} <- Accounts.get_hubspot_credential(user_id),
         {:ok, client} <- HubspotClient.build_client(credential),
         {:ok, results} <- HubspotClient.search_contacts(client, query: query, filters: filters) do

      Logger.info("Found #{length(results)} contacts")

      formatted_results = Enum.map(results, fn contact ->
        %{
          contact_id: contact["id"],
          name: "#{contact["properties"]["firstname"]} #{contact["properties"]["lastname"]}",
          email: contact["properties"]["email"],
          company: contact["properties"]["company"],
          lifecycle_stage: contact["properties"]["lifecyclestage"]
        }
      end)

      {:ok, %{
        results: formatted_results,
        count: length(results)
      }}
    else
      {:error, reason} = error ->
        Logger.error("Contact search failed: #{inspect(reason)}")
        error
    end
  end
end
```

#### 6. ScheduleMeeting Tool

**Location**: `lib/financial_agent/ai/tools/schedule_meeting.ex`

```elixir
defmodule FinancialAgent.AI.Tools.ScheduleMeeting do
  @moduledoc """
  Tool for creating calendar events.
  """

  require Logger
  alias FinancialAgent.{Accounts, Clients.CalendarClient}

  @doc """
  Schedule a calendar meeting.

  ## Parameters
    - title: Meeting title
    - attendees: List of attendee emails
    - start_time: ISO 8601 datetime
    - duration_minutes: Meeting duration
    - description: Meeting description (optional)

  ## Context
    - user_id: User scheduling the meeting
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)

    with {:ok, credential} <- Accounts.get_google_credential(user_id),
         {:ok, client} <- CalendarClient.build_client(credential),
         {:ok, event_params} <- build_event_params(params),
         {:ok, event} <- CalendarClient.create_event(client, event_params) do

      Logger.info("Meeting scheduled: #{event["id"]}")

      {:ok, %{
        event_id: event["id"],
        title: params["title"],
        start_time: params["start_time"],
        attendees: params["attendees"],
        link: event["htmlLink"]
      }}
    else
      {:error, reason} = error ->
        Logger.error("Failed to schedule meeting: #{inspect(reason)}")
        error
    end
  end

  defp build_event_params(params) do
    start_time = DateTime.from_iso8601(params["start_time"])
    duration = params["duration_minutes"]

    case start_time do
      {:ok, start_dt, _offset} ->
        end_dt = DateTime.add(start_dt, duration * 60, :second)

        event_params = %{
          summary: params["title"],
          description: params["description"] || "",
          start: %{dateTime: DateTime.to_iso8601(start_dt)},
          end: %{dateTime: DateTime.to_iso8601(end_dt)},
          attendees: Enum.map(params["attendees"], &%{email: &1})
        }

        {:ok, event_params}

      {:error, _} ->
        {:error, :invalid_datetime}
    end
  end
end
```

## Adding New Tools

### Step 1: Define Tool in Registry

Add tool definition to `ToolRegistry`:

```elixir
@tools Map.put(@tools, "my_new_tool", %{
  name: "my_new_tool",
  description: "Description of what the tool does",
  parameters: [
    %{name: "param1", type: "string", required: true, description: "First parameter"},
    %{name: "param2", type: "integer", required: false, description: "Optional parameter"}
  ],
  examples: [
    %{
      parameters: %{
        "param1" => "example value",
        "param2" => 42
      }
    }
  ]
})
```

### Step 2: Implement Tool Module

Create `lib/financial_agent/ai/tools/my_new_tool.ex`:

```elixir
defmodule FinancialAgent.AI.Tools.MyNewTool do
  @moduledoc """
  Description of the tool.
  """

  require Logger

  @doc """
  Execute the tool.

  ## Parameters
    - param1: Description
    - param2: Description (optional)

  ## Context
    - user_id: User context
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, term()}
  def execute(params, context) do
    user_id = Map.get(context, "user_id") || Map.get(context, :user_id)

    # Implement tool logic
    result = do_work(params, user_id)

    case result do
      {:ok, data} ->
        Logger.info("MyNewTool executed successfully")
        {:ok, data}

      {:error, reason} ->
        Logger.error("MyNewTool failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_work(params, user_id) do
    # Implementation
    {:ok, %{status: "success"}}
  end
end
```

### Step 3: Add Dispatch in ToolExecutor

Add dispatch case to `ToolExecutor`:

```elixir
defp dispatch_tool("my_new_tool", params, context) do
  Tools.MyNewTool.execute(params, context)
end
```

### Step 4: Test the Tool

Create `test/financial_agent/ai/tools/my_new_tool_test.exs`:

```elixir
defmodule FinancialAgent.AI.Tools.MyNewToolTest do
  use FinancialAgent.DataCase

  alias FinancialAgent.AI.Tools.MyNewTool

  describe "execute/2" do
    test "executes successfully with valid parameters" do
      user = insert(:user)

      params = %{
        "param1" => "test value",
        "param2" => 42
      }

      context = %{"user_id" => user.id}

      assert {:ok, result} = MyNewTool.execute(params, context)
      assert result.status == "success"
    end

    test "returns error for invalid parameters" do
      user = insert(:user)
      params = %{}  # Missing required param1
      context = %{"user_id" => user.id}

      assert {:error, _reason} = MyNewTool.execute(params, context)
    end
  end
end
```

## Best Practices

### 1. Tool Design

**Keep Tools Atomic**:
- Each tool should do one thing well
- Avoid complex multi-step tools
- Compose complex actions from multiple simple tools

**Example**:
```elixir
# Good - atomic tools
send_email(...)
create_task(...)

# Bad - complex tool
send_email_and_create_task_and_update_contact(...)
```

### 2. Parameter Validation

Always validate parameters before execution:

```elixir
defp validate_params(params) do
  with :ok <- validate_email(params["to"]),
       :ok <- validate_subject(params["subject"]),
       :ok <- validate_body(params["body"]) do
    {:ok, params}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

### 3. Error Handling

Return descriptive errors:

```elixir
# Good
{:error, "Invalid email address: #{email}"}
{:error, "Contact not found: #{contact_id}"}

# Bad
{:error, :failed}
{:error, "Error"}
```

### 4. Logging

Log tool execution for debugging:

```elixir
Logger.info("Executing #{tool_name} for user #{user_id}")
Logger.debug("Parameters: #{inspect(params)}")

# Log results
Logger.info("Tool executed successfully: #{inspect(result)}")

# Log errors with context
Logger.error("Tool failed: #{tool_name} - #{inspect(error)} - User: #{user_id}")
```

### 5. Context Usage

Always extract user_id from context:

```elixir
def execute(params, context) do
  # Handle both string and atom keys
  user_id = Map.get(context, "user_id") || Map.get(context, :user_id)

  if is_nil(user_id) do
    {:error, "Missing user_id in context"}
  else
    do_execute(params, user_id)
  end
end
```

## Testing Tools

### Unit Testing Individual Tools

```elixir
defmodule ToolTest do
  use ExUnit.Case
  import Mox

  test "tool executes successfully" do
    # Setup
    user = insert(:user)
    params = %{"param" => "value"}
    context = %{"user_id" => user.id}

    # Mock external services
    expect(ExternalServiceMock, :call, fn _ -> {:ok, %{}} end)

    # Execute
    assert {:ok, result} = MyTool.execute(params, context)
    assert result.status == "success"
  end
end
```

### Integration Testing with ToolExecutor

```elixir
@tag :integration
test "executes tool via ToolExecutor" do
  user = insert(:user)

  params = %{
    "to" => "test@example.com",
    "subject" => "Test",
    "body" => "Test email"
  }

  context = %{"user_id" => user.id}

  assert {:ok, result} = ToolExecutor.execute_tool("send_email", params, context)
  assert result.message_id
end
```

### Testing Tool Registry

```elixir
test "lists all available tools" do
  tools = ToolRegistry.list_tools()
  assert length(tools) > 0
  assert Enum.all?(tools, &Map.has_key?(&1, :name))
end

test "retrieves specific tool" do
  assert {:ok, tool} = ToolRegistry.get_tool("send_email")
  assert tool.name == "send_email"
  assert tool.description
  assert tool.parameters
end
```

## Monitoring & Debugging

### Track Tool Usage

```elixir
defmodule ToolExecutor do
  def execute_tool(tool_name, params, context) do
    start_time = System.monotonic_time(:millisecond)

    result = do_execute_tool(tool_name, params, context)

    duration = System.monotonic_time(:millisecond) - start_time

    # Log metrics
    :telemetry.execute(
      [:financial_agent, :tool, :execute],
      %{duration: duration},
      %{tool: tool_name, result: elem(result, 0)}
    )

    result
  end
end
```

### Debug Tool Execution

Enable debug logging:

```elixir
# In config/dev.exs
config :logger, level: :debug

# Check logs
[debug] Tool: send_email
[debug] Parameters: %{"to" => "test@example.com", "subject" => "Test"}
[debug] Context: %{"user_id" => "abc-123"}
[info] Email sent successfully to test@example.com
```

### Monitor Tool Errors

```elixir
# Count tool failures
from(j in Oban.Job,
  where: j.worker == "EventProcessorWorker",
  where: j.state == "retryable",
  where: fragment("args->>'tool' = ?", "send_email"),
  select: count(j.id)
)
|> Repo.one()
```

## Troubleshooting

### Tool Not Found

**Cause**: Tool not registered or dispatch case missing

**Solution**:
1. Check ToolRegistry has tool definition
2. Verify dispatch_tool/3 case exists in ToolExecutor
3. Ensure tool name matches exactly (case-sensitive)

### Missing Parameters

**Cause**: Required parameters not provided

**Solution**:
```elixir
# Check tool definition
{:ok, tool} = ToolRegistry.get_tool("send_email")
required = Enum.filter(tool.parameters, & &1.required)
IO.inspect(required, label: "Required parameters")
```

### Authentication Errors

**Cause**: Missing or expired credentials

**Solution**:
```elixir
# Verify credential exists
{:ok, credential} = Accounts.get_google_credential(user_id)

# Check expiration
if credential.expires_at < DateTime.utc_now() do
  # Refresh token
  Accounts.refresh_google_token(credential)
end
```

## Related Documentation

- [Architecture Overview](./01-architecture-overview.md)
- [Instructions System](./05-instructions-system.md)
- [Tasks System](./04-tasks-system.md)
- [RAG System](./03-rag-system.md)
