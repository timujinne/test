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

    # Permanent redirects from legacy /app/* trading URLs to /admin/*
    get "/app/:page", LegacyRedirectController, :show
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/live-dashboard", metrics: DashboardWeb.Telemetry
      forward "/dev/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # PhoenixKit routes (prefix configured in config/config.exs)
  phoenix_kit_routes()
end
