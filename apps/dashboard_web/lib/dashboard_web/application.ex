defmodule DashboardWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DashboardWeb.Telemetry,
      # PubSub is started in DataCollector.Application as BinanceSystem.PubSub
      DashboardWeb.Endpoint
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
