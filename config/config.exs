import Config

# Shared configuration for all applications
config :shared_data,
  ecto_repos: [SharedData.Repo]

# Phoenix PubSub is configured in each application's supervision tree
# (see apps/data_collector/lib/data_collector/application.ex)

# Import configuration for each application
import_config "../apps/shared_data/config/config.exs"
import_config "../apps/data_collector/config/config.exs"
import_config "../apps/trading_engine/config/config.exs"
import_config "../apps/dashboard_web/config/config.exs"

# Import environment specific config
import_config "#{config_env()}.exs"
