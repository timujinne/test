defmodule TradingEngine.AccountSupervisorTest do
  use ExUnit.Case, async: true

  alias TradingEngine.AccountSupervisor

  describe "trader_child_spec/2 (9a)" do
    test "restart is :temporary, not :transient" do
      child_spec = AccountSupervisor.trader_child_spec("account-1", setting_id: "setting-1")

      # :transient children are auto-restarted by DynamicSupervisor on any
      # abnormal exit, completely invisibly to StrategyManager's own crash
      # bookkeeping — producing a live trading process the UI believes is
      # stopped (the review's single CRITICAL finding). :temporary means a
      # crash simply stays down; recovery goes through
      # StrategyManager.start_strategy/1 explicitly instead.
      assert child_spec.restart == :temporary
    end

    test "child spec id is unique per setting_id and start args include the account_id" do
      child_spec = AccountSupervisor.trader_child_spec("account-1", setting_id: "setting-1")

      assert child_spec.id == {:trader, "setting-1"}
      assert {TradingEngine.Trader, :start_link, [opts]} = child_spec.start
      assert Keyword.get(opts, :account_id) == "account-1"
      assert Keyword.get(opts, :setting_id) == "setting-1"
    end
  end
end
