defmodule DataCollector.KrakenPrivateSupervisor do
  @moduledoc """
  `DynamicSupervisor` for `DataCollector.KrakenPrivateStream` processes --
  one per account with an active Kraken trader (see
  `DataCollector.KrakenPrivateStream` moduledoc). Paired with the
  `DataCollector.KrakenPrivateRegistry` `Registry` (both started under
  `DataCollector.Application`) for account_id -> pid lookup via `:via`
  naming. Identical shape to `DataCollector.OKXPrivateSupervisor`.
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
