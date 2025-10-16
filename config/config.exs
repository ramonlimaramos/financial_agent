# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :financial_agent,
  ecto_repos: [FinancialAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :financial_agent, FinancialAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FinancialAgentWeb.ErrorHTML, json: FinancialAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FinancialAgent.PubSub,
  live_view: [signing_salt: "P3ildtp6"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :financial_agent, FinancialAgent.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  financial_agent: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  financial_agent: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth for OAuth
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.compose https://www.googleapis.com/auth/calendar",
         hd: nil
       ]}
    # HubSpot uses custom OAuth implementation, not Ueberauth
  ]

# Configure Oban for background jobs
config :financial_agent, Oban,
  repo: FinancialAgent.Repo,
  queues: [sync: 5, embeddings: 10, events: 10, gmail_monitor: 3, tasks: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Run Gmail monitor every 2 minutes (configurable via GMAIL_MONITOR_INTERVAL)
       {"*/2 * * * *", FinancialAgent.Workers.GmailMonitorWorker}
     ]}
  ]

# Configure Cloak
config :financial_agent, FinancialAgent.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("REp4S0M3SWlvZE1ValFNT1FWV0pxU0dIaHdlTDBvak4=")}
  ]

# Configure Tesla to suppress deprecation warning
config :tesla, disable_deprecated_builder_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
