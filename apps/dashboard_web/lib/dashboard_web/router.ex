defmodule DashboardWeb.Router do
  use DashboardWeb, :router

  import PhoenixKitWeb.Integration

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DashboardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PhoenixKitWeb.Plugs.Integration
    # Fetch current user and scope for all browser requests (needed for avatar in layouts)
    plug PhoenixKitWeb.Users.Auth, :fetch_phoenix_kit_current_user
    plug PhoenixKitWeb.Users.Auth, :fetch_phoenix_kit_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Redirect root to blog
  scope "/", DashboardWeb do
    pipe_through :browser
    get "/", PageController, :home
  end

  # Public routes - Blog (no authentication required)
  scope "/", DashboardWeb do
    pipe_through :browser

    live_session :public,
      layout: {DashboardWeb.Layouts, :public},
      on_mount: [{PhoenixKitWeb.Users.Auth, :phoenix_kit_mount_current_scope}] do
      live "/articles", BlogLive
      live "/articles/:slug", BlogPostLive
    end
  end

  # Protected routes - Trading App (authentication required)
  # Note: phoenix_kit_ensure_authenticated includes mount_current_scope internally
  scope "/app", DashboardWeb do
    pipe_through :browser

    live_session :trading_app,
      layout: {DashboardWeb.Layouts, :trading_dashboard},
      on_mount: [{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated}] do
      live "/trading", TradingLive
      live "/portfolio", PortfolioLive
      live "/orders", OrdersLive
      live "/history", HistoryLive
      live "/strategies", StrategiesLive
      live "/chains", ChainsLive
      live "/accounts", SettingsLive
    end
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/live-dashboard", metrics: DashboardWeb.Telemetry
    end
  end

  # PhoenixKit routes (prefix configured in config/config.exs)
  phoenix_kit_routes()
end
