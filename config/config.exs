import Config

config :swoosh, api_client: Swoosh.ApiClient.Finch

config :phoenix_kit,
  parent_app_name: :dashboard_web,
  parent_module: DashboardWeb,
  repo: SharedData.Repo

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

# Configure esbuild (Javascript bundling)
config :esbuild,
  version: "0.19.8",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/dashboard_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../apps/dashboard_web/assets/node_modules", __DIR__)}
  ]

# Configure tailwind (CSS bundling)
config :tailwind,
  version: "4.1.8",
  default: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/dashboard_web/assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
