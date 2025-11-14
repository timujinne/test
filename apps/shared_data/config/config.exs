import Config

# Configure SharedData Repo
config :shared_data, SharedData.Repo,
  database: "binance_trading_repo",
  pool_size: 10

# Cloak Vault configuration is handled in environment-specific config files
# (dev.exs, test.exs, runtime.exs) to avoid compile-time decoding issues
