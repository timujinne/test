import Config

# Print only warnings and errors during test
config :logger, level: :warning

# Configure test environment
config :binance_system,
  env: :test
