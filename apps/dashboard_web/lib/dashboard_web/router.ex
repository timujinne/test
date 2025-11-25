defmodule DashboardWeb.Router do
  use DashboardWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DashboardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DashboardWeb do
    pipe_through :browser

    live_session :default,
      layout: {DashboardWeb.Layouts, :drawer} do
      live "/", TradingLive
      live "/trading", TradingLive
      live "/portfolio", PortfolioLive
      live "/history", HistoryLive
      live "/settings", SettingsLive
    end
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/admin", metrics: DashboardWeb.Telemetry
    end
  end
end
