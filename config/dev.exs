import Config

# Configure Logger for development
config :logger, :console, format: "[$level] $message\n"

# Set development-only config here
config :binance_system,
  env: :dev
