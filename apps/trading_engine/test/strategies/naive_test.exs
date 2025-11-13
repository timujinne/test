defmodule TradingEngine.Strategies.NaiveTest do
  use ExUnit.Case, async: true
  alias TradingEngine.Strategies.Naive

  describe "init/1" do
    test "initializes with default configuration" do
      config = %{
        "symbol" => "BTCUSDT"
      }

      assert {:ok, state} = Naive.init(config)
      assert state.symbol == "BTCUSDT"
      assert Decimal.equal?(state.buy_down_interval, Decimal.new("0.01"))
      assert Decimal.equal?(state.sell_up_interval, Decimal.new("0.01"))
      assert Decimal.equal?(state.quantity, Decimal.new("0.001"))
      assert state.last_price == nil
      assert state.position == nil
    end

    test "initializes with custom configuration" do
      config = %{
        "symbol" => "ETHUSDT",
        "buy_down_interval" => "0.02",
        "sell_up_interval" => "0.03",
        "quantity" => "0.01"
      }

      assert {:ok, state} = Naive.init(config)
      assert state.symbol == "ETHUSDT"
      assert Decimal.equal?(state.buy_down_interval, Decimal.new("0.02"))
      assert Decimal.equal?(state.sell_up_interval, Decimal.new("0.03"))
      assert Decimal.equal?(state.quantity, Decimal.new("0.01"))
    end
  end

  describe "on_tick/2 - buy logic" do
    test "does not buy when last_price is nil" do
      {:ok, state} = Naive.init(%{"symbol" => "BTCUSDT"})

      market_data = %{"c" => "50000.00"}

      assert {action, new_state} = Naive.on_tick(market_data, state)
      assert action == :noop
      assert Decimal.equal?(new_state.last_price, Decimal.new("50000.00"))
    end

    test "does not buy when price increases" do
      {:ok, state} = Naive.init(%{"symbol" => "BTCUSDT"})
      state = %{state | last_price: Decimal.new("50000.00")}

      market_data = %{"c" => "50500.00"}  # Price increased by 1%

      assert {:noop, new_state} = Naive.on_tick(market_data, state)
      assert Decimal.equal?(new_state.last_price, Decimal.new("50500.00"))
    end

    test "buys when price drops by more than buy_down_interval" do
      {:ok, state} = Naive.init(%{
        "symbol" => "BTCUSDT",
        "buy_down_interval" => "0.01",  # 1%
        "quantity" => "0.001"
      })
      state = %{state | last_price: Decimal.new("50000.00")}

      # Price drops by 1.5% (below threshold)
      market_data = %{"c" => "49250.00"}

      assert {{:place_order, order}, new_state} = Naive.on_tick(market_data, state)
      assert order.symbol == "BTCUSDT"
      assert order.side == "BUY"
      assert order.type == "MARKET"
      assert Decimal.equal?(order.quantity, Decimal.new("0.001"))
      assert Decimal.equal?(new_state.last_price, Decimal.new("49250.00"))
    end

    test "does not buy when already has position" do
      {:ok, state} = Naive.init(%{
        "symbol" => "BTCUSDT",
        "buy_down_interval" => "0.01"
      })
      state = %{
        state |
        last_price: Decimal.new("50000.00"),
        position: %{entry_price: Decimal.new("48000.00"), quantity: Decimal.new("0.001")}
      }

      # Price drops significantly
      market_data = %{"c" => "49000.00"}

      assert {:noop, new_state} = Naive.on_tick(market_data, state)
      assert new_state.position != nil
    end
  end

  describe "on_tick/2 - sell logic" do
    test "does not sell when no position" do
      {:ok, state} = Naive.init(%{"symbol" => "BTCUSDT"})
      state = %{state | last_price: Decimal.new("50000.00")}

      market_data = %{"c" => "51000.00"}

      assert {:noop, _new_state} = Naive.on_tick(market_data, state)
    end

    test "sells when price rises above sell_up_interval from entry" do
      {:ok, state} = Naive.init(%{
        "symbol" => "BTCUSDT",
        "sell_up_interval" => "0.01",  # 1%
        "quantity" => "0.001"
      })

      entry_price = Decimal.new("50000.00")
      state = %{
        state |
        position: %{entry_price: entry_price, quantity: Decimal.new("0.001")}
      }

      # Price increases by 1.5% from entry (above threshold)
      market_data = %{"c" => "50750.00"}

      assert {{:place_order, order}, new_state} = Naive.on_tick(market_data, state)
      assert order.symbol == "BTCUSDT"
      assert order.side == "SELL"
      assert order.type == "MARKET"
      assert Decimal.equal?(order.quantity, Decimal.new("0.001"))
    end

    test "does not sell when price increase is below threshold" do
      {:ok, state} = Naive.init(%{
        "symbol" => "BTCUSDT",
        "sell_up_interval" => "0.01"  # 1%
      })

      entry_price = Decimal.new("50000.00")
      state = %{
        state |
        position: %{entry_price: entry_price, quantity: Decimal.new("0.001")}
      }

      # Price increases by only 0.5% (below threshold)
      market_data = %{"c" => "50250.00"}

      assert {:noop, new_state} = Naive.on_tick(market_data, state)
      assert new_state.position != nil
    end
  end

  describe "on_execution/2" do
    test "updates position on BUY execution" do
      {:ok, state} = Naive.init(%{"symbol" => "BTCUSDT"})

      execution = %{
        "x" => "TRADE",
        "S" => "BUY",
        "L" => "50000.00",  # Last executed price
        "l" => "0.001"       # Last executed quantity
      }

      assert {:noop, new_state} = Naive.on_execution(execution, state)
      assert new_state.position != nil
      assert Decimal.equal?(new_state.position.entry_price, Decimal.new("50000.00"))
      assert Decimal.equal?(new_state.position.quantity, Decimal.new("0.001"))
    end

    test "clears position on SELL execution" do
      {:ok, state} = Naive.init(%{"symbol" => "BTCUSDT"})
      state = %{
        state |
        position: %{entry_price: Decimal.new("50000.00"), quantity: Decimal.new("0.001")}
      }

      execution = %{
        "x" => "TRADE",
        "S" => "SELL",
        "L" => "51000.00",
        "l" => "0.001"
      }

      assert {:noop, new_state} = Naive.on_execution(execution, state)
      assert new_state.position == nil
    end

    test "ignores non-TRADE executions" do
      {:ok, state} = Naive.init(%{"symbol" => "BTCUSDT"})

      execution = %{
        "x" => "NEW",
        "S" => "BUY"
      }

      assert {:noop, new_state} = Naive.on_execution(execution, state)
      assert new_state == state
    end
  end

  describe "complete trading cycle" do
    test "executes full buy-sell cycle" do
      # Initialize strategy
      {:ok, state} = Naive.init(%{
        "symbol" => "BTCUSDT",
        "buy_down_interval" => "0.01",
        "sell_up_interval" => "0.01",
        "quantity" => "0.001"
      })

      # Step 1: First price tick (establishes baseline)
      market_data_1 = %{"c" => "50000.00"}
      {:noop, state} = Naive.on_tick(market_data_1, state)
      assert Decimal.equal?(state.last_price, Decimal.new("50000.00"))
      assert state.position == nil

      # Step 2: Price drops 2% - triggers BUY
      market_data_2 = %{"c" => "49000.00"}
      {{:place_order, buy_order}, state} = Naive.on_tick(market_data_2, state)
      assert buy_order.side == "BUY"

      # Step 3: Buy execution received
      buy_execution = %{
        "x" => "TRADE",
        "S" => "BUY",
        "L" => "49000.00",
        "l" => "0.001"
      }
      {:noop, state} = Naive.on_execution(buy_execution, state)
      assert state.position != nil
      assert Decimal.equal?(state.position.entry_price, Decimal.new("49000.00"))

      # Step 4: Price rises 2% from entry - triggers SELL
      market_data_3 = %{"c" => "49980.00"}
      {{:place_order, sell_order}, state} = Naive.on_tick(market_data_3, state)
      assert sell_order.side == "SELL"

      # Step 5: Sell execution received
      sell_execution = %{
        "x" => "TRADE",
        "S" => "SELL",
        "L" => "49980.00",
        "l" => "0.001"
      }
      {:noop, state} = Naive.on_execution(sell_execution, state)
      assert state.position == nil
    end
  end
end
