import Config

config :dashboard_web, DashboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_at_least_64_bytes_long_for_security"

config :dashboard_web, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

# Use local Swoosh adapter so sent emails appear in /dev/mailbox
config :phoenix_kit, PhoenixKit.Mailer, adapter: Swoosh.Adapters.Local

# Disable session fingerprinting in dev — ephemeral ports change on every TCP connection
# when behind a proxy that includes port in X-Forwarded-For (e.g. IP:port format),
# causing constant IP mismatch false positives. Enable only in production.
config :phoenix_kit,
  session_fingerprint_enabled: false

config :swoosh, :api_client, false
