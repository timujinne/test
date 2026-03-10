import Config

config :dashboard_web,
  ecto_repos: [SharedData.Repo]

config :dashboard_web, DashboardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: DashboardWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: BinanceSystem.PubSub,
  live_view: [signing_salt: "Ry5tN9wK4mQ2"]  # LiveView signing salt

config :dashboard_web,
  generators: [context_app: :shared_data]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Configure PhoenixKit
# Note: layouts_module and phoenix_version_strategy are in config/runtime.exs
# to avoid compile-time warnings when phoenix_kit is compiled before dashboard_web
config :phoenix_kit,
  repo: SharedData.Repo,
  url_prefix: "",
  from_email: "noreply@trading.local",
  from_name: "Trading Dashboard"

# Configure rate limiting with Hammer
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       # Cleanup expired rate limit buckets every 60 seconds
       expiry_ms: 60_000,
       # Cleanup interval (1 minute)
       cleanup_interval_ms: 60_000
     ]}

# Configure rate limits for authentication endpoints
config :phoenix_kit, PhoenixKit.Users.RateLimiter,
  # Login: 5 attempts per minute per email
  login_limit: 5,
  login_window_ms: 60_000,
  # Magic link: 3 requests per 5 minutes per email
  magic_link_limit: 3,
  magic_link_window_ms: 300_000,
  # Password reset: 3 requests per 5 minutes per email
  password_reset_limit: 3,
  password_reset_window_ms: 300_000,
  # Registration: 3 attempts per hour per email
  registration_limit: 3,
  registration_window_ms: 3_600_000,
  # Registration IP: 10 attempts per hour per IP
  registration_ip_limit: 10,
  registration_ip_window_ms: 3_600_000

# Configure Ueberauth (minimal configuration for compilation)
# Applications using PhoenixKit should configure their own providers
config :ueberauth, Ueberauth, providers: %{}

# Configure Oban for PhoenixKit background jobs
# Required for file processing (storage system) and email handling
config :dashboard_web, Oban,
  repo: SharedData.Repo,
  queues: [
    default: 10,
    emails: 50,
    file_processing: 20,
    posts: 10,
    sitemap: 5,
    sqs_polling: 1,
    sync: 5,
    shop_imports: 2
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", PhoenixKit.ScheduledJobs.Workers.ProcessScheduledJobsWorker}
     ]}
  ]
