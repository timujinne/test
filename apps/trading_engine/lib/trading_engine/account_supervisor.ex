defmodule TradingEngine.AccountSupervisor do
  @moduledoc """
  DynamicSupervisor for managing Trader processes.
  One Trader process per strategy (setting_id).
  """
  require Logger

  alias SharedData.Types

  @doc """
  Start a trader for a specific strategy setting.
  """
  def start_trader(account_id, opts) do
    DynamicSupervisor.start_child(__MODULE__, trader_child_spec(account_id, opts))
  end

  @doc false
  # Exposed (undocumented) so account_supervisor_test.exs can assert on the
  # child spec's `restart:` value directly, since DynamicSupervisor.which_children/1
  # doesn't surface it (dynamic children are tracked as `:undefined` ids).
  @spec trader_child_spec(Types.account_id(), keyword()) :: Supervisor.child_spec()
  def trader_child_spec(account_id, opts) do
    setting_id = Keyword.fetch!(opts, :setting_id)

    %{
      id: {:trader, setting_id},
      start: {TradingEngine.Trader, :start_link, [Keyword.put(opts, :account_id, account_id)]},
      # :temporary (not :transient!) — a crashed Trader must simply stay down.
      # :transient children are auto-restarted by DynamicSupervisor on any
      # abnormal exit using the original start_link args, completely
      # independently of and invisibly to StrategyManager's own
      # Process.monitor-based crash bookkeeping (which reacts to the same
      # crash by deactivating the DB row and forgetting the trader). That
      # combination produces a live trading process the rest of the app —
      # including the UI's stop button, which routes through StrategyManager —
      # believes is stopped. Recovery after a crash is handled explicitly via
      # StrategyManager.start_strategy/1, which invokes Trader.init/1's
      # check_for_recovery/4 path; it must never happen invisibly at the
      # supervisor level.
      restart: :temporary,
      # Give Trader.terminate/2 time to cancel open orders on stop instead of the
      # default 5s, which can brutally kill it mid-cancellation and orphan orders.
      shutdown: 30_000
    }
  end

  @doc """
  Stop a trader by setting_id.
  """
  def stop_trader(setting_id) do
    case Registry.lookup(TradingEngine.TraderRegistry, setting_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Stop a trader by account_id (legacy, stops first found).
  """
  def stop_trader_by_account(account_id) do
    case Registry.lookup(TradingEngine.TraderRegistry, {:account, account_id}) do
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
