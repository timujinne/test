import Config
config :phoenix_kit, repo: SharedData.Repo

# Binance API configuration for testing (mock values)
config :binance,
  api_key: "test_api_key",
  secret_key: "test_secret_key",
  end_point: "https://testnet.binance.vision"

# OKX API configuration for testing (mock values, always demo — deterministic
# regardless of any OKX_* env vars set in the host/CI environment)
config :data_collector, :okx,
  base_url: "https://www.okx.com",
  demo: true,
  ws_public_url: "wss://wspap.okx.com:8443/ws/v5/public",
  ws_private_url: "wss://wspap.okx.com:8443/ws/v5/private"

# Kraken API configuration for testing (mock values, deterministic
# regardless of any KRAKEN_* env vars set in the host/CI environment)
config :data_collector, :kraken,
  base_url: "https://api.kraken.com",
  ws_url: "wss://ws.kraken.com/v2"

# Coinbase API configuration for testing (mock values, deterministic
# regardless of any COINBASE_* env vars set in the host/CI environment)
config :data_collector, :coinbase,
  base_url: "https://api.coinbase.com",
  ws_public_url: "wss://advanced-trade-ws.coinbase.com",
  ws_user_url: "wss://advanced-trade-ws-user.coinbase.com"

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

# Same reasoning as above: StrategyManager's 1s-delayed :restore_active_strategies
# boot restoration has no Sandbox checkout and would eventually raise
# DBConnection.OwnershipError against the Sandbox-owned Repo once any test
# run in this VM takes longer than ~1s (see strategy_manager.ex's init/1).
config :trading_engine, :restore_on_boot, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
