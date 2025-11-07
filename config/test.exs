import Config

# Configure database for testing
config :shared_data, SharedData.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  database: "binance_trading_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Print only warnings and errors during test
config :logger, level: :warning

# Configure test Binance API keys (use testnet)
config :binance,
  api_key: System.get_env("BINANCE_API_KEY") || "test_api_key",
  secret_key: System.get_env("BINANCE_SECRET_KEY") || "test_secret_key",
  end_point: "https://testnet.binance.vision"

# Use a test cloak key
config :shared_data, SharedData.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8="),
      iv_length: 12
    }
  ]
