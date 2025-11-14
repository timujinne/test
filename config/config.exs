import Config

# Import configuration for each application
# Note: import_config does not support wildcard patterns, import each explicitly
import_config "../apps/shared_data/config/config.exs"
import_config "../apps/data_collector/config/config.exs"
import_config "../apps/trading_engine/config/config.exs"
import_config "../apps/dashboard_web/config/config.exs"

# Import environment specific config
import_config "#{config_env()}.exs"
