defmodule DataCollector.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: BinanceSystem.PubSub},
      DataCollector.CircuitBreaker,
      DataCollector.RateLimiter,
      DataCollector.MarketData
    ]

    opts = [strategy: :one_for_one, name: DataCollector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
