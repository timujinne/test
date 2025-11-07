import Config

# Configure database for development
config :shared_data, SharedData.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  database: System.get_env("POSTGRES_DB") || "binance_trading_dev",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10"),
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

# Configure Binance API for development (testnet)
config :binance,
  api_key: System.get_env("BINANCE_API_KEY"),
  secret_key: System.get_env("BINANCE_SECRET_KEY"),
  end_point: System.get_env("BINANCE_BASE_URL") || "https://testnet.binance.vision"

# Cloak encryption - use a dev key if not provided
config :shared_data, SharedData.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: decode_cloak_key(System.get_env("CLOAK_KEY")),
      iv_length: 12
    }
  ]

# Helper function to decode cloak key with fallback
defp decode_cloak_key(nil) do
  # Development-only fallback key - DO NOT use in production
  Base.decode64!("tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8=")
end

defp decode_cloak_key(key) do
  Base.decode64!(key)
end

# Set log level
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
