defmodule DashboardWeb.Application do
  @moduledoc """
  The DashboardWeb Application Service.

  This application provides the Phoenix web interface for the Binance Trading System.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      DashboardWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: DashboardWeb.PubSub},
      # Start the Endpoint (http/https)
      DashboardWeb.Endpoint
      # Start a worker by calling: DashboardWeb.Worker.start_link(arg)
      # {DashboardWeb.Worker, arg}
    ]

    opts = [strategy: :one_for_one, name: DashboardWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
