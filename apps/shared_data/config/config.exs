import Config

# Ecto repos configuration
config :shared_data,
  ecto_repos: [SharedData.Repo]

# Configure SharedData Repo
config :shared_data, SharedData.Repo,
  database: "binance_trading_repo",
  pool_size: 10

# Cloak Vault configuration is handled in environment-specific config files
# (dev.exs, test.exs, runtime.exs) to avoid compile-time decoding issues
