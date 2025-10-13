# Architecture Overview

## System Design

FinancialAgent is built using a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────┐
│                        Web Layer                             │
│  LiveView Components, Controllers, WebSockets               │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                    Business Logic Layer                      │
│  Contexts: Instructions, Tasks, Chat, Accounts              │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                      Service Layer                           │
│  AI Services, External API Clients, RAG                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   Background Jobs Layer                      │
│  Oban Workers: Sync, Embeddings, Events, Monitoring         │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                    Data Layer                                │
│  PostgreSQL with Pgvector, Ecto Schemas                      │
└─────────────────────────────────────────────────────────────┘
```

## Core Domains

### 1. Accounts & Authentication
**Location**: `lib/financial_agent/accounts/`

Manages users and their OAuth credentials:
- User registration and authentication
- OAuth token storage with Cloak encryption
- Token refresh and expiration handling
- Multi-provider support (Google, HubSpot)

**Key Models:**
- `User`: Basic user information and settings
- `Credential`: OAuth tokens per provider per user

### 2. Instructions (Event-Driven Automation)
**Location**: `lib/financial_agent/instructions/`

Rule-based automation system:
- Users create instructions in plain English
- LLM evaluates events against instruction conditions
- Automatic action execution when conditions match

**Key Components:**
- `Instruction`: Schema for automation rules
- `Matcher`: LLM-based event evaluation
- `Executor`: Action interpretation and tool execution

### 3. Tasks (Stateful Workflows)
**Location**: `lib/financial_agent/tasks/`

Multi-turn agent workflows:
- Complex tasks requiring multiple steps
- Conversation history tracking
- State machine for status transitions
- User interaction support

**Key Components:**
- `Task`: Main task entity with status tracking
- `TaskMessage`: Conversation history
- `StateMachine`: Status transition validation
- `Agent`: LLM orchestration and decision making

### 4. RAG (Retrieval Augmented Generation)
**Location**: `lib/financial_agent/rag/`

Semantic search and retrieval:
- Vector embeddings for Gmail and HubSpot data
- Pgvector for similarity search
- Automatic data sync and embedding generation

**Key Components:**
- `Chunk`: Vector storage with metadata
- `Retrieval`: Semantic search functionality
- `Embeddings`: OpenAI embedding generation

### 5. AI Services
**Location**: `lib/financial_agent/ai/`

LLM integration and orchestration:
- OpenAI API client with streaming support
- Tool registry and execution
- Prompt building and management

**Key Components:**
- `LLMClient`: Chat completions and streaming
- `ToolExecutor`: Dynamic tool calling
- `ToolRegistry`: Available tools catalog
- `Embeddings`: Text-to-vector conversion

### 6. External Clients
**Location**: `lib/financial_agent/clients/`

Third-party API integrations:
- Gmail API for email access
- HubSpot API for CRM data
- Calendar API for scheduling

**Key Components:**
- `GmailClient`: Email operations
- `HubspotClient`: Contact and deal management
- `CalendarClient`: Event management

### 7. Background Workers
**Location**: `lib/financial_agent/workers/`

Asynchronous job processing:
- Data synchronization
- Embedding generation
- Event processing
- Gmail monitoring

**Key Components:**
- `GmailSyncWorker`: Sync Gmail data
- `HubspotSyncWorker`: Sync HubSpot data
- `GenerateEmbeddingsWorker`: Create vector embeddings
- `EventProcessorWorker`: Process instruction events
- `GmailMonitorWorker`: Poll for new emails (cron)
- `TaskExecutorWorker`: Execute stateful tasks

## Data Flow

### Instructions Flow

```
1. User creates instruction via UI
   ↓
2. GmailMonitorWorker polls Gmail API (every 2 minutes)
   ↓
3. New email detected
   ↓
4. EventProcessorWorker enqueued with email data
   ↓
5. Matcher evaluates email against user's instructions
   ↓
6. If match found (confidence > 0.7):
   ↓
7. Executor interprets action_text via LLM
   ↓
8. ToolExecutor executes appropriate tool
   ↓
9. Result stored/logged
```

### Tasks Flow

```
1. Instruction action triggers task creation
   OR
   User manually creates task
   ↓
2. Task created with status: pending
   ↓
3. TaskExecutorWorker picks up task
   ↓
4. Agent.execute_step called:
   - Analyzes task and conversation history
   - Decides next action via LLM
   - Executes tools or requests user input
   ↓
5. Status transitions:
   - pending → in_progress
   - in_progress → waiting_for_input (if needs input)
   - in_progress → completed (if done)
   - in_progress → failed (if error)
   ↓
6. If continue needed: re-enqueue worker
   If waiting_for_input: pause until user responds
   If completed/failed: terminal state
```

### RAG Flow

```
1. Background sync workers run:
   - GmailSyncWorker
   - HubspotSyncWorker
   ↓
2. Data fetched and stored as Chunks
   ↓
3. GenerateEmbeddingsWorker processes chunks:
   - Calls OpenAI embeddings API
   - Stores 1536-dimension vectors in Pgvector
   ↓
4. User asks question in chat
   ↓
5. Query embedded via OpenAI
   ↓
6. Pgvector cosine similarity search
   ↓
7. Top K relevant chunks retrieved
   ↓
8. Context + query sent to LLM
   ↓
9. LLM response with citations
```

## Technology Stack

### Core Framework
- **Phoenix 1.7.14**: Web framework
- **LiveView**: Real-time UI without JavaScript
- **Ecto 3.10+**: Database wrapper and query builder

### Database
- **PostgreSQL 14+**: Primary database
- **Pgvector**: Vector similarity search extension

### AI/ML
- **OpenAI GPT-4o**: Chat completions and reasoning
- **text-embedding-3-small**: Vector embeddings (1536 dimensions)

### Background Processing
- **Oban Pro**: Reliable job processing with cron support
- **5 Queues**: sync, embeddings, events, gmail_monitor, tasks

### External APIs
- **Google OAuth**: Gmail and Calendar access
- **HubSpot OAuth**: CRM data access

### Security
- **Cloak**: Encrypted OAuth token storage
- **CSRF Protection**: Built-in Phoenix security
- **Secure Headers**: Helmet-style security headers

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Load Balancer                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
       ┌───────────────┴───────────────┐
       │                               │
┌──────▼──────┐               ┌───────▼──────┐
│   Phoenix   │               │   Phoenix    │
│   Node 1    │               │   Node 2     │
└──────┬──────┘               └───────┬──────┘
       │                               │
       └───────────────┬───────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                      PostgreSQL                              │
│                    (with Pgvector)                           │
└─────────────────────────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                     Oban Workers                             │
│  (Distributed across Phoenix nodes)                          │
└─────────────────────────────────────────────────────────────┘
```

## Scaling Considerations

### Horizontal Scaling
- Phoenix nodes can be added behind load balancer
- Oban jobs distribute across nodes automatically
- Database connection pooling per node

### Vertical Scaling
- Increase Oban worker counts per queue
- Adjust PostgreSQL connection pool size
- Increase LLM API rate limits

### Caching
- LiveView tracks state in memory
- ETS for session storage
- Consider Redis for distributed cache (future)

## Security Model

### Authentication
- OAuth 2.0 for external services
- Session-based authentication
- CSRF token validation

### Authorization
- User-scoped data access
- Row-level security via Ecto queries
- API credentials encrypted at rest

### Data Protection
- OAuth tokens encrypted with Cloak
- Database credentials in environment variables
- Secrets never committed to repository

## Monitoring & Observability

### Telemetry
- Phoenix Telemetry for request metrics
- Oban dashboard for job monitoring
- Custom events for business metrics

### Logging
- Structured logging with Logger
- Request ID tracking
- Error tracking and aggregation

### Development Tools
- LiveDashboard for real-time metrics
- Swoosh mailbox for email preview
- IEx for interactive debugging

## Related Documentation

- [Oban Workers](./02-oban-workers.md)
- [RAG System](./03-rag-system.md)
- [Tasks System](./04-tasks-system.md)
- [Instructions System](./05-instructions-system.md)
- [Events & Tools](./06-events-and-tools.md)
