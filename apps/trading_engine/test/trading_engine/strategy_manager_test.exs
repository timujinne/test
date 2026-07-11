defmodule TradingEngine.StrategyManagerTest do
  use ExUnit.Case, async: false

  alias TradingEngine.StrategyManager

  # StrategyManager is a VM-wide singleton (started once by trading_engine's
  # application supervisor), so we can't start a second GenServer under the
  # same registered name to exercise init/1's scheduling branch in isolation.
  # Instead we call StrategyManager.init/1 directly as a plain function —
  # since it isn't spawned via GenServer.start_link, `self()` inside it is
  # THIS test process, so Process.send_after(self(), :restore_active_strategies,
  # 1000) delivers straight to our own mailbox. That lets us assert on
  # whether the message was scheduled with plain assert_receive/refute_receive,
  # without mocking Process.send_after or touching the real singleton
  # (and, not incidentally, without ever needing a DB/Sandbox checkout —
  # init/1 itself makes no DB calls; only the eventual :restore_active_strategies
  # handler does, which is exactly the hazard this guard exists to avoid).
  describe "restore-on-boot scheduling (10b)" do
    test "does not schedule :restore_active_strategies when :restore_on_boot is false" do
      previous = Application.get_env(:trading_engine, :restore_on_boot)
      Application.put_env(:trading_engine, :restore_on_boot, false)
      on_exit(fn -> put_or_delete_env(previous) end)

      assert {:ok, _state} = StrategyManager.init([])

      refute_receive :restore_active_strategies, 1200
    end

    test "still schedules (and fires) :restore_active_strategies when :restore_on_boot is true — matches production default" do
      previous = Application.get_env(:trading_engine, :restore_on_boot)
      Application.put_env(:trading_engine, :restore_on_boot, true)
      on_exit(fn -> put_or_delete_env(previous) end)

      assert {:ok, _state} = StrategyManager.init([])

      assert_receive :restore_active_strategies, 1200
    end

    test "defaults to scheduling when :restore_on_boot is unset (matches config/test.exs's explicit false, not this implicit default)" do
      previous = Application.get_env(:trading_engine, :restore_on_boot)
      Application.delete_env(:trading_engine, :restore_on_boot)
      on_exit(fn -> put_or_delete_env(previous) end)

      assert {:ok, _state} = StrategyManager.init([])

      assert_receive :restore_active_strategies, 1200
    end
  end

  defp put_or_delete_env(nil), do: Application.delete_env(:trading_engine, :restore_on_boot)
  defp put_or_delete_env(value), do: Application.put_env(:trading_engine, :restore_on_boot, value)
end
