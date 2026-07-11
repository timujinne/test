defmodule DataCollector.CoinbasePrivateSupervisor do
  @moduledoc """
  `DynamicSupervisor` for `DataCollector.CoinbasePrivateStream` processes --
  one per account with an active Coinbase trader (see
  `DataCollector.CoinbasePrivateStream` moduledoc). Paired with the
  `DataCollector.CoinbasePrivateRegistry` `Registry` (both started under
  `DataCollector.Application`) for account_id -> pid lookup via `:via`
  naming. Identical shape to `DataCollector.OKXPrivateSupervisor`/
  `DataCollector.KrakenPrivateSupervisor`.
  """
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
