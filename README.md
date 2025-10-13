# FinancialAgent

> An AI-powered automation platform that connects to your Gmail, HubSpot, and Calendar to automate workflows with natural language instructions.

FinancialAgent uses GPT-4o to understand your instructions and automatically perform actions based on events like new emails or contacts. Create rules like "When I get an email about pricing, send our pricing doc" and let AI handle it.

## Features

### 🤖 AI Chat Assistant

- Natural language conversations with context from your Gmail and HubSpot
- RAG (Retrieval Augmented Generation) for accurate responses from your data
- Streaming responses for real-time interaction
- Tool calling for dynamic actions (search contacts, retrieve emails)

### 📋 Instructions System (Event-Driven Automation)

- Create AI-powered automation rules in plain English
- **Trigger Types**: New Email, New Contact, Scheduled
- **Automatic Matching**: LLM evaluates events against your conditions
- **Smart Actions**: AI interprets your instructions and calls appropriate tools
- **Gmail Monitoring**: Polls Gmail API every 2 minutes for new emails
- Real-time UI for managing instructions

### 📊 Stateful Task System (Multi-Turn Workflows)

- Complex tasks that require multiple steps and user interaction
- **Task Types**: Schedule Meeting, Compose Email, Research, Data Analysis, Custom
- **State Machine**: Tracks task progress (pending → in_progress → completed)
- **Conversation History**: Full audit trail of agent interactions
- **User Input Handling**: Tasks can pause and wait for your input
- **Retry Mechanism**: Failed tasks can be retried with one click

### 🔐 OAuth Integration

- Google OAuth for Gmail and Calendar access
- HubSpot OAuth for CRM data access
- Secure token storage with Cloak encryption

### 🔍 RAG (Retrieval Augmented Generation)

- Pgvector for semantic search across your data
- Automatic embeddings for Gmail and HubSpot data
- Background sync workers with Oban

## Tech Stack

- **Framework**: Phoenix 1.7.14 with LiveView
- **Language**: Elixir 1.14+
- **Database**: PostgreSQL with Pgvector extension
- **AI**: OpenAI GPT-4o for chat, embeddings, and tool calling
- **Background Jobs**: Oban for async tasks and cron jobs
- **UI**: Tailwind CSS with Phoenix Components
- **OAuth**: Ueberauth for Google and custom HubSpot integration

## Getting Started

### Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- PostgreSQL 14+ with Pgvector extension
- OpenAI API key
- Google OAuth credentials (for Gmail/Calendar)
- HubSpot OAuth credentials (optional)

### Installation

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd financial_agent
   ```

2. **Install dependencies**

   ```bash
   mix deps.get
   ```

3. **Configure environment variables**

   Create a `.env` file in the project root:

   ```bash
   # Database
   DATABASE_URL=ecto://postgres:postgres@localhost/financial_agent_dev

   # OpenAI
   OPENAI_API_KEY=sk-...
   OPENAI_ORG_KEY=org-...  # Optional
   OPENAI_EMBEDDING_MODEL=text-embedding-3-small
   OPENAI_CHAT_MODEL=gpt-4o

   # Google OAuth
   GOOGLE_CLIENT_ID=your-google-client-id
   GOOGLE_CLIENT_SECRET=your-google-client-secret

   # HubSpot OAuth (optional)
   HUBSPOT_CLIENT_ID=your-hubspot-client-id
   HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret

   # Instructions System
   GMAIL_MONITOR_INTERVAL=2  # Minutes between Gmail checks
   ```

4. **Setup database**

   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

5. **Start the server**

   ```bash
   mix phx.server
   ```

   Or inside IEx:

   ```bash
   iex -S mix phx.server
   ```

6. **Visit the application**

   Open [http://localhost:4000](http://localhost:4000) in your browser.

## Usage

### Creating Instructions

1. Navigate to **Instructions** in the top navigation
2. Click **New Instruction**
3. Select a trigger type (e.g., "New Email")
4. Describe the condition: "Email mentions pricing or quote request"
5. Describe the action: "Send them our pricing document link from the knowledge base"
6. Save and activate the instruction

The system will now automatically monitor for matching events and execute your action.

### Managing Tasks

1. Navigate to **Tasks** in the top navigation
2. View all tasks created by your instructions
3. Filter by status: All, Active, Completed, Failed
4. Click on a task to view details and conversation history
5. Submit input if a task is waiting for your response
6. Retry failed tasks if needed

### Using the Chat

1. Navigate to **Chat** in the top navigation
2. Authenticate with Google and/or HubSpot
3. Ask questions about your emails or contacts
4. The AI will search your data and provide contextual responses

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/financial_agent/instructions_test.exs

# Run with coverage
mix test --cover
```

### Code Quality

```bash
# Format code
mix format

# Check formatting
mix format --check-formatted

# Run Credo (if configured)
mix credo --strict

# Type checking with Dialyzer (if configured)
mix dialyzer
```

### Database Operations

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate)
mix ecto.reset

# Generate new migration
mix ecto.gen.migration migration_name
```

## Architecture

### Context Organization

- **Accounts**: User management and OAuth credentials
- **Instructions**: Event-driven automation rules
- **Tasks**: Stateful multi-turn workflows
- **Chat**: Conversation management
- **AI**: LLM client, embeddings, tool execution
- **RAG**: Retrieval and semantic search
- **Clients**: Gmail, HubSpot, Calendar API clients
- **Workers**: Background jobs (sync, embeddings, monitoring, events, tasks)

### Key Patterns

**Instructions Flow:**

```
Gmail Monitor (Cron) → New Email Event →
Matcher (LLM evaluation) → Executor (Tool calls) → Result
```

**Tasks Flow:**

```
Instruction Action → Create Task →
Agent (LLM orchestration) → Tools/User Input →
State Transitions → Completion
```

**RAG Flow:**

```
Gmail/HubSpot Sync → Generate Embeddings →
Store in Pgvector → User Query →
Semantic Search → LLM Response
```

## Project Structure

```
lib/
├── financial_agent/              # Business logic
│   ├── accounts/                 # Users and credentials
│   ├── ai/                       # LLM client, embeddings, tools
│   ├── chat/                     # Conversation management
│   ├── clients/                  # External API clients
│   ├── instructions/             # Event-driven automation
│   ├── rag/                      # Retrieval and search
│   ├── tasks/                    # Stateful workflows
│   └── workers/                  # Background jobs
├── financial_agent_web/          # Web layer
│   ├── components/               # Phoenix components
│   ├── controllers/              # Controllers
│   └── live/                     # LiveView modules
│       ├── chat_live.ex
│       ├── instructions_live/
│       └── tasks_live/
priv/
├── repo/migrations/              # Database migrations
└── static/                       # Static assets
test/                             # Test files
```

## Configuration

Key configurations in `config/runtime.exs`:

- OpenAI API settings
- OAuth credentials
- Gmail monitor interval
- Database connection

## Background Jobs

**Oban Queues:**

- `sync` (5 workers): Gmail and HubSpot data sync
- `embeddings` (10 workers): Generate vector embeddings
- `events` (10 workers): Process instruction events
- `gmail_monitor` (3 workers): Poll Gmail API
- `tasks` (5 workers): Execute stateful task workflows

**Cron Jobs:**

- Gmail Monitor: Runs every 2 minutes (configurable)

## Contributing

### Code Style

- Follow Elixir conventions (snake_case, PascalCase for modules)
- Use `@spec` for public function signatures
- Add `@moduledoc` and `@doc` for documentation
- Run `mix format` before committing
- Keep functions small and focused
- Prefer DRY functions over nested cases

### Testing Guidelines

- Write unit tests for business logic
- Use ExMachina factories for test data
- Test edge cases and error conditions
- Use `async: true` for tests without shared state
- Tag integration tests with `@tag :integration`

### Pull Request Process

1. Create a feature branch from `main`
2. Write tests for new functionality
3. Ensure all tests pass: `mix test`
4. Format code: `mix format`
5. Update documentation if needed
6. Submit PR with clear description

## Deployment

For production deployment:

1. Set `PHX_SERVER=true` environment variable
2. Configure `SECRET_KEY_BASE` (generate with `mix phx.gen.secret`)
3. Set production database URL
4. Configure OAuth credentials
5. Set OpenAI API key
6. Ensure Pgvector extension is available
7. Run migrations: `mix ecto.migrate`
8. Build assets: `mix assets.deploy`

See [Phoenix deployment guide](https://hexdocs.pm/phoenix/deployment.html) for more details.

## Troubleshooting

### Common Issues

**OAuth not working:**

- Verify redirect URIs match your OAuth app settings
- Check credentials are loaded in environment
- Ensure proper scopes are requested

**Gmail monitoring not triggering:**

- Check OPENAI_API_KEY is set
- Verify user has Google credentials stored
- Check Oban cron job is running: visit `/dev/dashboard` in development

**Pgvector errors:**

- Ensure Pgvector extension is installed in PostgreSQL
- Run `CREATE EXTENSION IF NOT EXISTS vector;` in psql

**Tests failing:**

- Ensure test database exists: `mix ecto.create`
- Run migrations: `MIX_ENV=test mix ecto.migrate`
- Check factory data is valid

## License

Copyright © 2024

## Learn More

- **Phoenix Framework**: https://www.phoenixframework.org/
- **Elixir**: https://elixir-lang.org/
- **OpenAI API**: https://platform.openai.com/docs
- **Pgvector**: https://github.com/pgvector/pgvector
- **Oban**: https://hexdocs.pm/oban
