import Config

config :swoosh, api_client: Swoosh.ApiClient.Finch

config :phoenix_kit,
  parent_app_name: :dashboard_web,
  parent_module: DashboardWeb,
  repo: SharedData.Repo,
  url_prefix: "/phoenix_kit"

# Trading navigation — injected into PhoenixKit's admin sidebar ABOVE the
# built-in groups (group priority < admin_main's 100). Each tab's `live_view`
# auto-generates its route inside the shared :phoenix_kit_admin live_session,
# so trading pages inherit PhoenixKit auth + admin chrome (header + sidebar).
config :phoenix_kit, :admin_dashboard_tabs, [
  %{
    id: :trading_chart,
    label: "Trading",
    icon: "hero-chart-bar",
    path: "/admin/trading",
    live_view: {DashboardWeb.TradingLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 10
  },
  %{
    id: :trading_portfolio,
    label: "Portfolio",
    icon: "hero-wallet",
    path: "/admin/portfolio",
    live_view: {DashboardWeb.PortfolioLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 11
  },
  %{
    id: :trading_orders,
    label: "Orders",
    icon: "hero-clipboard-document-list",
    path: "/admin/orders",
    live_view: {DashboardWeb.OrdersLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 12
  },
  %{
    id: :trading_history,
    label: "History",
    icon: "hero-clock",
    path: "/admin/history",
    live_view: {DashboardWeb.HistoryLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 13
  },
  %{
    id: :trading_strategies,
    label: "Strategies",
    icon: "hero-cpu-chip",
    path: "/admin/strategies",
    live_view: {DashboardWeb.StrategiesLive, :index},
    permission: "dashboard",
    group: :trading_automation,
    priority: 20
  },
  %{
    id: :trading_chains,
    label: "Chains",
    icon: "hero-link",
    path: "/admin/chains",
    live_view: {DashboardWeb.ChainsLive, :index},
    permission: "dashboard",
    group: :trading_automation,
    priority: 21
  },
  %{
    id: :trading_accounts,
    label: "Accounts",
    icon: "hero-key",
    path: "/admin/accounts",
    live_view: {DashboardWeb.SettingsLive, :index},
    permission: "dashboard",
    group: :trading_automation,
    priority: 22
  }
]

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
