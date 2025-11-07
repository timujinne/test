import Config

# Configure production settings
config :logger, level: :info

# Runtime configuration (for secrets)
if config_env() == :prod do
  # Example: Load secrets from environment variables
  # config :binance_system,
  #   binance_api_key: System.get_env("BINANCE_API_KEY"),
  #   binance_secret_key: System.get_env("BINANCE_SECRET_KEY")
end
