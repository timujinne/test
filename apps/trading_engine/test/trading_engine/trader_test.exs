defmodule TradingEngine.TraderTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias TradingEngine.RiskManager
  alias TradingEngine.Trader

  # `handle_info({:execution_report, ...})` goes through the pre-existing
  # `owns_execution?/2` / `update_order_in_db/1`, which fall back to real
  # `SharedData.Repo` queries (`order_belongs_to_account?/2`,
  # `SharedData.Trading.update_order_status/3`). Umbrella-wide `mix test`
  # runs every app's suite in one BEAM session against the same
  # `SharedData.Repo` pool; once any other app's `test_helper.exs` (e.g.
  # shared_data's or dashboard_web's) puts the sandbox into `:manual` mode,
  # these tests need their own explicit checkout — otherwise they raise
  # `DBConnection.OwnershipError` whenever they happen to run after that
  # mode switch. Checking out here (rather than relying on the pool's
  # default `:auto` mode) makes these tests correct and DB-isolated
  # regardless of run order or which other suites already ran.
  setup do
    :ok = Sandbox.checkout(SharedData.Repo)
  end

  # Minimal strategy stub — Trader.handle_info/2 and Trader.terminate/2 both
  # call into `state.strategy`, so a real (if trivial) module implementing
  # `TradingEngine.Strategy` is needed. Every callback is a pure no-op; only
  # `Trader`'s own position-tracking/unsubscribe logic is under test here.
  defmodule NoopStrategy do
    @moduledoc false
    @behaviour TradingEngine.Strategy

    @impl true
    def init(_config), do: {:ok, %{}}

    @impl true
    def on_tick(_market_data, state), do: {:noop, state}

    @impl true
    def on_execution(_execution, state), do: {:noop, state}
  end

  # Builds a minimal but structurally-complete Trader state map (every key
  # `handle_info({:execution_report, ...}, _)` and `terminate/2` read from).
  # `account_id` is deliberately a plain string, never a real DB id: the
  # ownership check in these tests always short-circuits via `state.orders`
  # (see `execution/5`'s pre-populated order id), so the
  # `order_belongs_to_account?/2` DB fallback — which would otherwise cast
  # `account_id` against `accounts.id` (`:binary_id`) — is never reached.
  defp base_state(overrides) do
    Map.merge(
      %{
        account_id: "test-account",
        setting_id: "test-setting",
        exchange: "binance",
        credentials: %{},
        strategy: NoopStrategy,
        strategy_state: %{},
        strategy_config: %{},
        symbol: "BTCUSDT",
        symbols: ["BTCUSDT"],
        subscribed_symbols: ["BTCUSDT"],
        positions: %{},
        orders: %{},
        last_cum_qty_by_order: %{},
        subscribed_to_ticks: true,
        timer_refs: []
      },
      overrides
    )
  end

  # Builds a Binance-shaped execution report. `order_id` is pre-registered
  # in `state.orders` by the caller so `owns_execution?/2` recognizes it
  # without touching the DB.
  defp execution(order_id, symbol, side, status, cum_qty) do
    %{
      "i" => order_id,
      "s" => symbol,
      "S" => side,
      "X" => status,
      "x" => status,
      "z" => cum_qty,
      "q" => cum_qty,
      "l" => cum_qty,
      "L" => "50000.0"
    }
  end

  describe "handle_info({:execution_report, ...}) position tracking (9c)" do
    test "a BUY fill increases positions by the incremental delta, not the raw cumulative value, across two PARTIALLY_FILLED pushes for the same order" do
      state = base_state(%{orders: %{"o1" => %{}}})

      exec1 = execution("o1", "BTCUSDT", "BUY", "PARTIALLY_FILLED", "0.02")
      assert {:noreply, state1} = Trader.handle_info({:execution_report, exec1}, state)

      assert Decimal.equal?(state1.positions["BTCUSDT"].quantity, Decimal.new("0.02"))
      assert Decimal.equal?(state1.last_cum_qty_by_order["o1"], Decimal.new("0.02"))

      # Second push carries the new cumulative fill (0.05 total), not a
      # second independent 0.05 fill. Naively adding the raw "z" value here
      # would double count and land on 0.07.
      exec2 = execution("o1", "BTCUSDT", "BUY", "PARTIALLY_FILLED", "0.05")
      assert {:noreply, state2} = Trader.handle_info({:execution_report, exec2}, state1)

      assert Decimal.equal?(state2.positions["BTCUSDT"].quantity, Decimal.new("0.05"))
      assert Decimal.equal?(state2.last_cum_qty_by_order["o1"], Decimal.new("0.05"))
    end

    test "a SELL fill decreases positions by the incremental delta" do
      state =
        base_state(%{
          orders: %{"o2" => %{}},
          positions: %{"BTCUSDT" => %{quantity: Decimal.new("0.05")}}
        })

      exec = execution("o2", "BTCUSDT", "SELL", "FILLED", "0.03")
      assert {:noreply, new_state} = Trader.handle_info({:execution_report, exec}, state)

      assert Decimal.equal?(new_state.positions["BTCUSDT"].quantity, Decimal.new("0.02"))
    end

    test "an execution report for an order this Trader does not own leaves positions untouched" do
      state = base_state(%{orders: %{}})

      exec = execution("someone-elses-order", "BTCUSDT", "BUY", "FILLED", "0.5")
      assert {:noreply, new_state} = Trader.handle_info({:execution_report, exec}, state)

      assert new_state.positions == %{}
      assert new_state.last_cum_qty_by_order == %{}
    end

    test "RiskManager now actually rejects an order that would exceed the position cap once fills are tracked" do
      state = base_state(%{orders: %{"o3" => %{}}})

      exec = execution("o3", "BTCUSDT", "BUY", "FILLED", "0.95")
      assert {:noreply, state_after_fill} = Trader.handle_info({:execution_report, exec}, state)

      order_params = %{symbol: "BTCUSDT", side: "BUY", quantity: "0.1"}

      # Minimal risk-check state (no account_id) mirrors risk_manager_test.exs'
      # existing convention and keeps this test focused on position sizing.
      risk_state = %{positions: state_after_fill.positions}

      assert {:error, message} = RiskManager.check_order(order_params, risk_state)
      assert message =~ "Position size would exceed maximum"
    end
  end

  describe "terminate/2 unsubscribes via the exchange-aware MarketStream facade, not the Binance-only TickerStream (9b)" do
    test "an OKX trader's terminate decrements OKXPublicStream's subscriber count, leaving Binance's TickerStream untouched" do
      symbol = "OKXTERMTEST"
      :ets.insert(:okx_public_subscribers, {symbol, 2})
      :ets.delete(:ticker_subscribers, symbol)

      state =
        base_state(%{
          exchange: "okx",
          symbol: symbol,
          symbols: [symbol],
          subscribed_symbols: [symbol]
        })

      assert :ok = Trader.terminate(:normal, state)

      assert :ets.lookup(:okx_public_subscribers, symbol) == [{symbol, 1}]
      assert :ets.lookup(:ticker_subscribers, symbol) == []
    end

    test "a Binance trader's terminate still decrements TickerStream's subscriber count" do
      symbol = "BNBTERMTEST"
      :ets.insert(:ticker_subscribers, {symbol, 2})

      state =
        base_state(%{
          exchange: "binance",
          symbol: symbol,
          symbols: [symbol],
          subscribed_symbols: [symbol]
        })

      assert :ok = Trader.terminate(:normal, state)

      assert :ets.lookup(:ticker_subscribers, symbol) == [{symbol, 1}]
    end
  end
end
