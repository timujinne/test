defmodule DataCollector.OKXPrivateSupervisor do
  @moduledoc """
  `DynamicSupervisor` for `DataCollector.OKXPrivateStream` processes — one
  per account with an active OKX trader (see `DataCollector.OKXPrivateStream`
  moduledoc). Paired with the `DataCollector.OKXPrivateRegistry` `Registry`
  (both started under `DataCollector.Application`) for account_id -> pid
  lookup via `:via` naming.
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
