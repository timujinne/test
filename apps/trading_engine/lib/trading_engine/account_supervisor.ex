defmodule TradingEngine.AccountSupervisor do
  @moduledoc """
  DynamicSupervisor for managing Trader processes.
  One Trader process per account.
  """
  require Logger

  def start_trader(account_id, opts) do
    child_spec = %{
      id: TradingEngine.Trader,
      start: {TradingEngine.Trader, :start_link, [Keyword.put(opts, :account_id, account_id)]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_trader(account_id) do
    case Registry.lookup(TradingEngine.TraderRegistry, account_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  def list_traders do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
