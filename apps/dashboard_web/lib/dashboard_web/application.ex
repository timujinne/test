defmodule DashboardWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Ensure layout module is loaded before PhoenixKit.Supervisor starts
    # This prevents "[PhoenixKit] Layout module not found" warnings
    Code.ensure_loaded!(DashboardWeb.Layouts)

    children = [
      PhoenixKit.Supervisor,
      {Finch, [name: Swoosh.Finch]},
      DashboardWeb.Telemetry,
      # PubSub is started in DataCollector.Application as BinanceSystem.PubSub
      DashboardWeb.Endpoint,
      {Oban, Application.get_env(:dashboard_web, Oban)}
    ]

    opts = [strategy: :one_for_one, name: DashboardWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
