defmodule DataCollector.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS table for ticker stream subscriber counts
    # This table tracks how many processes are subscribed to each symbol's ticker stream
    :ets.new(:ticker_subscribers, [:named_table, :public, :set])

    children = [
      {Phoenix.PubSub, name: BinanceSystem.PubSub},
      {Registry, keys: :unique, name: DataCollector.StreamRegistry},
      DataCollector.CircuitBreaker,
      DataCollector.RateLimiter,
      DataCollector.MarketData
    ]

    opts = [strategy: :one_for_one, name: DataCollector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
