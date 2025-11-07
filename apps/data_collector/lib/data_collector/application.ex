defmodule DataCollector.Application do
  @moduledoc """
  The DataCollector Application Service.

  This application collects market data from Binance via REST API and WebSocket.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Rate limiter to respect Binance API limits
      DataCollector.RateLimiter,
      # Market data aggregator
      DataCollector.MarketData
      # WebSocket connection manager (commented for now - will be implemented)
      # {DataCollector.WebSocket.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: DataCollector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
