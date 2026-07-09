defmodule DataCollector.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS table for ticker stream subscriber counts
    # This table tracks how many processes are subscribed to each symbol's ticker stream
    :ets.new(:ticker_subscribers, [:named_table, :public, :set])

    # Same, for DataCollector.OKXPublicStream's single-connection subscriber
    # counts (see its moduledoc for why it's one shared connection rather
    # than one process per symbol like TickerStream).
    :ets.new(:okx_public_subscribers, [:named_table, :public, :set])

    children = [
      {Phoenix.PubSub, name: BinanceSystem.PubSub},
      {Registry, keys: :unique, name: DataCollector.StreamRegistry},
      # account_id -> DataCollector.OKXPrivateStream pid, paired with the
      # DynamicSupervisor below (see OKXPrivateStream's moduledoc).
      {Registry, keys: :unique, name: DataCollector.OKXPrivateRegistry},
      DataCollector.OKXPrivateSupervisor,
      DataCollector.CircuitBreaker,
      DataCollector.RateLimiter,
      DataCollector.MarketData,
      DataCollector.OKX.Symbols
    ]

    opts = [strategy: :one_for_one, name: DataCollector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
