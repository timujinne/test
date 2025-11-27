defmodule TradingEngine.AccountSupervisor do
  @moduledoc """
  DynamicSupervisor for managing Trader processes.
  One Trader process per strategy (setting_id).
  """
  require Logger

  @doc """
  Start a trader for a specific strategy setting.
  """
  def start_trader(account_id, opts) do
    setting_id = Keyword.fetch!(opts, :setting_id)

    child_spec = %{
      id: {:trader, setting_id},
      start: {TradingEngine.Trader, :start_link, [Keyword.put(opts, :account_id, account_id)]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
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
