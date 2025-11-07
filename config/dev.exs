import Config

# Configure shared_data repository
config :shared_data, SharedData.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "binance_trading_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configure logger
config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:request_id]

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
