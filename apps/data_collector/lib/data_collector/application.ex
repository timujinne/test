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

    # Monotonic counter backing DataCollector.Kraken.Auth.next_nonce/0 — see
    # its moduledoc for why a public ETS counter (rather than per-call
    # wall-clock reads) is the safe, race-free way to satisfy Kraken's
    # "always increasing, never resettable" nonce requirement.
    :ets.new(:kraken_nonce, [:named_table, :public, :set])

    # Same, for DataCollector.KrakenPublicStream's single-connection
    # subscriber counts (see its moduledoc — same rationale as
    # :okx_public_subscribers above).
    :ets.new(:kraken_public_subscribers, [:named_table, :public, :set])

    # Same, for DataCollector.CoinbasePublicStream's single-connection
    # subscriber counts (see its moduledoc — same rationale as
    # :okx_public_subscribers/:kraken_public_subscribers above).
    :ets.new(:coinbase_public_subscribers, [:named_table, :public, :set])

    children = [
      {Phoenix.PubSub, name: BinanceSystem.PubSub},
      {Registry, keys: :unique, name: DataCollector.StreamRegistry},
      # account_id -> DataCollector.OKXPrivateStream pid, paired with the
      # DynamicSupervisor below (see OKXPrivateStream's moduledoc).
      {Registry, keys: :unique, name: DataCollector.OKXPrivateRegistry},
      DataCollector.OKXPrivateSupervisor,
      # account_id -> DataCollector.KrakenPrivateStream pid, paired with the
      # DynamicSupervisor below (see KrakenPrivateStream's moduledoc).
      {Registry, keys: :unique, name: DataCollector.KrakenPrivateRegistry},
      DataCollector.KrakenPrivateSupervisor,
      # account_id -> DataCollector.CoinbasePrivateStream pid, paired with
      # the DynamicSupervisor below (see CoinbasePrivateStream's moduledoc).
      {Registry, keys: :unique, name: DataCollector.CoinbasePrivateRegistry},
      DataCollector.CoinbasePrivateSupervisor,
      DataCollector.CircuitBreaker,
      DataCollector.RateLimiter,
      DataCollector.MarketData,
      DataCollector.OKX.Symbols,
      DataCollector.Kraken.Symbols,
      # Lookup-only, like OKX.Symbols/Kraken.Symbols — the ETS table it
      # needs is created in its own init/1, no separate table wiring here.
      DataCollector.Coinbase.Products
    ]

    opts = [strategy: :one_for_one, name: DataCollector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
