import Config

# Configure the binance system namespace
config :binance_system,
  ecto_repos: [SharedData.Repo]

# Configure shared_data app
config :shared_data,
  ecto_repos: [SharedData.Repo]

# Configure Phoenix PubSub for inter-service communication
config :binance_system, BinanceSystem.PubSub,
  name: BinanceSystem.PubSub,
  adapter: Phoenix.PubSub.PG2

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
