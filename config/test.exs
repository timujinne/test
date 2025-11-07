import Config

# Binance API configuration for testing (mock values)
config :binance,
  api_key: "test_api_key",
  secret_key: "test_secret_key",
  end_point: "https://testnet.binance.vision"

# Cloak encryption for testing
config :shared_data, SharedData.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8="),
      iv_length: 12
    }
  ]

# Configure shared_data repository for testing
config :shared_data, SharedData.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "binance_trading_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
