# Configuration Guide

This document lists all environment variables used by the FinancialAgent application.

## Environment Variables

| Variable Name | Description | Example Value |
|---------------|-------------|---------------|
| `CLOAK_KEY` | Base64-encoded encryption key for Cloak Vault, used to encrypt OAuth tokens and sensitive data in the database | `UkVwNFNrTTNTV2x2ZEUxVWFsRk5UMUZXV0dweFUwZElhSGQzVERCdmFrND0=` |
| `DATABASE_URL` | PostgreSQL connection string for Ecto database connection | `postgres://postgres:password@localhost/financial_agent_prod` |
| `DNS_CLUSTER_QUERY` | DNS query for Elixir distributed clustering (optional, only needed for multi-node deployments) | `financial-agent.internal` |
| `ECTO_IPV6` | Enable IPv6 support for database connections (optional, set to "true" or "1") | `true` |
| `GOOGLE_CLIENT_ID` | Google OAuth 2.0 Client ID for user authentication and Gmail API access | `713790438191-abc123.apps.googleusercontent.com` |
| `GOOGLE_CLIENT_SECRET` | Google OAuth 2.0 Client Secret for authentication | `GOCSPX-abc123def456ghi789` |
| `HUBSPOT_CLIENT_ID` | HubSpot OAuth 2.0 Client ID for CRM integration | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| `HUBSPOT_CLIENT_SECRET` | HubSpot OAuth 2.0 Client Secret for token exchange | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| `OPENAI_API_KEY` | OpenAI API key for generating text embeddings using text-embedding-3-small model | `sk-proj-abc123def456ghi789` |
| `OPENAI_ORG_KEY` | OpenAI Organization ID for API requests (optional, only needed for multi-org accounts) | `org-abc123def456` |
| `PHX_HOST` | Public hostname where the application is accessible | `financial-agent-twilight-butterfly-8679.fly.dev` |
| `PHX_SERVER` | Controls whether Phoenix server starts automatically in releases (set to any value to enable) | `true` |
| `POOL_SIZE` | Database connection pool size for Ecto (optional, defaults to 10) | `10` |
| `PORT` | Port number where Phoenix server listens for HTTP requests | `8080` |
| `SECRET_KEY_BASE` | Secret key for signing and encrypting cookies, sessions, and tokens (64+ characters) | `abc123def456...` (generate with `mix phx.gen.secret`) |

## Required vs Optional

**Required for Production:**
- `CLOAK_KEY`
- `DATABASE_URL`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `HUBSPOT_CLIENT_ID`
- `HUBSPOT_CLIENT_SECRET`
- `OPENAI_API_KEY`
- `PHX_HOST`
- `PORT`
- `SECRET_KEY_BASE`

**Optional (have defaults):**
- `DNS_CLUSTER_QUERY` (defaults to `:ignore`)
- `ECTO_IPV6` (defaults to IPv4)
- `OPENAI_ORG_KEY` (not needed for single-org accounts)
- `PHX_SERVER` (handled by deployment platform)
- `POOL_SIZE` (defaults to `10`)

## Generating Secrets

```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret

# Generate CLOAK_KEY
mix phx.gen.secret 32 | base64
```

## Setting Secrets on Fly.io

```bash
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly secrets set CLOAK_KEY="your_base64_key"
fly secrets set GOOGLE_CLIENT_ID="your_google_id"
fly secrets set GOOGLE_CLIENT_SECRET="your_google_secret"
fly secrets set HUBSPOT_CLIENT_ID="your_hubspot_id"
fly secrets set HUBSPOT_CLIENT_SECRET="your_hubspot_secret"
fly secrets set OPENAI_API_KEY="sk-your_key"

# Verify secrets
fly secrets list
```

## Development Environment

Create a `.env` file in the project root (not committed to Git):

```bash
GOOGLE_CLIENT_ID=your_dev_client_id
GOOGLE_CLIENT_SECRET=your_dev_client_secret
HUBSPOT_CLIENT_ID=your_dev_hubspot_id
HUBSPOT_CLIENT_SECRET=your_dev_hubspot_secret
OPENAI_API_KEY=sk-your_dev_key
CLOAK_KEY=your_base64_encoded_key
```
