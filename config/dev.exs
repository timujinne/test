import Config

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
      key: Base.decode64!(System.get_env("CLOAK_KEY") || "tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8="),
      iv_length: 12
    }
  ]

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
