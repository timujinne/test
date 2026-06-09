import Config
config :phoenix_kit, repo: SharedData.Repo

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
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432"),
  database: "binance_trading_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Disable Oban queues, Cron and Pruner under test so background jobs do not
# run against the Sandbox-owned Repo (avoids ownership errors / flaky boots).
config :dashboard_web, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
