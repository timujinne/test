import Config

# Shared configuration for all applications
config :binance_system,
  ecto_repos: [SharedData.Repo]

# Phoenix PubSub for inter-application communication
config :binance_system, BinanceSystem.PubSub,
  name: BinanceSystem.PubSub,
  adapter: Phoenix.PubSub.PG2

# Import configuration for each application
import_config "../apps/*/config/config.exs"

# Import environment specific config
import_config "#{config_env()}.exs"
