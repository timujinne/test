import Config
config :phoenix_kit, PhoenixKit.Mailer, adapter: Swoosh.Adapters.Local

# Binance API configuration for development (using testnet)
config :binance,
  api_key: System.get_env("BINANCE_API_KEY") || "test_api_key",
  secret_key: System.get_env("BINANCE_SECRET_KEY") || "test_secret_key",
  end_point: System.get_env("BINANCE_BASE_URL") || "https://testnet.binance.vision"

# Cloak encryption for development
config :shared_data, SharedData.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key:
        Base.decode64!(
          System.get_env("CLOAK_KEY") || "tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8="
        ),
      iv_length: 12
    }
  ]

# Configure shared_data repository
config :shared_data, SharedData.Repo,
  username: System.get_env("APP_DB_USER") || "postgres",
  password: System.get_env("APP_DB_PASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "postgres",
  database: System.get_env("APP_DB_NAME") || "binance_trading_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configure Phoenix endpoint for development
config :dashboard_web, DashboardWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "dev_secret_key_base_at_least_64_bytes_long_for_development_only_replace_in_production",
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/dashboard_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Configure logger
config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:request_id]

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# LiveView debug options for Tidewave MCP
config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true
