defmodule TradingEngine.Strategies.GridTest do
  use ExUnit.Case, async: true
  alias TradingEngine.Strategies.Grid

  describe "init/1" do
    test "initializes with default configuration" do
      config = %{"symbol" => "BTCUSDT"}

      assert {:ok, state} = Grid.init(config)
      assert state.symbol == "BTCUSDT"
      assert state.grid_levels == 5
      assert Decimal.equal?(state.grid_spacing, Decimal.new("0.005"))
      assert Decimal.equal?(state.quantity_per_grid, Decimal.new("0.001"))
      assert state.base_price == nil
      assert state.active_orders == []
    end

    test "initializes with custom configuration" do
      config = %{
        "symbol" => "ETHUSDT",
        "grid_levels" => 10,
        "grid_spacing" => "0.01",
        "quantity_per_grid" => "0.05"
      }

      assert {:ok, state} = Grid.init(config)
      assert state.symbol == "ETHUSDT"
      assert state.grid_levels == 10
      assert Decimal.equal?(state.grid_spacing, Decimal.new("0.01"))
      assert Decimal.equal?(state.quantity_per_grid, Decimal.new("0.05"))
    end
  end

  describe "on_tick/2 - grid initialization" do
    test "initializes grid on first price tick" do
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_levels" => 3,
        "grid_spacing" => "0.01",
        "quantity_per_grid" => "0.001"
      })

      market_data = %{"c" => "50000.00"}

      assert {{:place_order, orders}, new_state} = Grid.on_tick(market_data, state)

      # Should create buy and sell orders (3 levels each = 6 orders)
      assert is_list(orders)
      assert length(orders) == 6

      # Should set base_price
      assert Decimal.equal?(new_state.base_price, Decimal.new("50000.00"))
    end

    test "does not recreate grid on subsequent ticks" do
      {:ok, state} = Grid.init(%{"symbol" => "BTCUSDT"})
      state = %{state | base_price: Decimal.new("50000.00")}

      market_data = %{"c" => "50100.00"}

      assert {:noop, new_state} = Grid.on_tick(market_data, state)
      assert Decimal.equal?(new_state.base_price, Decimal.new("50100.00"))
    end

    test "creates correct buy orders below base price" do
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_levels" => 3,
        "grid_spacing" => "0.01"  # 1%
      })

      market_data = %{"c" => "50000.00"}
      {{:place_order, orders}, _state} = Grid.on_tick(market_data, state)

      buy_orders = Enum.filter(orders, fn o -> o.side == "BUY" end)
      assert length(buy_orders) == 3

      # Check prices are below base price at correct intervals
      [order1, order2, order3] = Enum.sort_by(buy_orders, & &1.price, {:desc, Decimal})

      assert Decimal.compare(order1.price, Decimal.new("50000.00")) == :lt
      assert Decimal.compare(order2.price, order1.price) == :lt
      assert Decimal.compare(order3.price, order2.price) == :lt

      # First buy order should be 1% below base
      expected_price1 = Decimal.mult(Decimal.new("50000.00"), Decimal.new("0.99"))
      assert Decimal.equal?(order1.price, expected_price1)
    end

    test "creates correct sell orders above base price" do
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_levels" => 3,
        "grid_spacing" => "0.01"
      })

      market_data = %{"c" => "50000.00"}
      {{:place_order, orders}, _state} = Grid.on_tick(market_data, state)

      sell_orders = Enum.filter(orders, fn o -> o.side == "SELL" end)
      assert length(sell_orders) == 3

      # Check prices are above base price
      [order1, order2, order3] = Enum.sort_by(sell_orders, & &1.price, {:asc, Decimal})

      assert Decimal.compare(order1.price, Decimal.new("50000.00")) == :gt
      assert Decimal.compare(order2.price, order1.price) == :gt
      assert Decimal.compare(order3.price, order2.price) == :gt

      # First sell order should be 1% above base
      expected_price1 = Decimal.mult(Decimal.new("50000.00"), Decimal.new("1.01"))
      assert Decimal.equal?(order1.price, expected_price1)
    end

    test "all orders are LIMIT orders with GTC" do
      {:ok, state} = Grid.init(%{"symbol" => "BTCUSDT", "grid_levels" => 2})

      market_data = %{"c" => "50000.00"}
      {{:place_order, orders}, _state} = Grid.on_tick(market_data, state)

      assert Enum.all?(orders, fn o ->
        o.type == "LIMIT" and o.timeInForce == "GTC"
      end)
    end
  end

  describe "on_execution/2 - order rebalancing" do
    test "places sell order after buy execution" do
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_spacing" => "0.01",
        "quantity_per_grid" => "0.001"
      })

      execution = %{
        "x" => "TRADE",
        "i" => "12345",
        "S" => "BUY",
        "L" => "49500.00"  # Executed at this price
      }

      assert {{:place_order, order}, _new_state} = Grid.on_execution(execution, state)

      # Should place sell order 1% above execution price
      assert order.side == "SELL"
      assert order.type == "LIMIT"
      expected_price = Decimal.mult(Decimal.new("49500.00"), Decimal.new("1.01"))
      assert Decimal.equal?(order.price, expected_price)
      assert Decimal.equal?(order.quantity, Decimal.new("0.001"))
    end

    test "places buy order after sell execution" do
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_spacing" => "0.01",
        "quantity_per_grid" => "0.001"
      })

      execution = %{
        "x" => "TRADE",
        "i" => "12346",
        "S" => "SELL",
        "L" => "50500.00"
      }

      assert {{:place_order, order}, _new_state} = Grid.on_execution(execution, state)

      # Should place buy order 1% below execution price
      assert order.side == "BUY"
      assert order.type == "LIMIT"
      expected_price = Decimal.mult(Decimal.new("50500.00"), Decimal.new("0.99"))
      assert Decimal.equal?(order.price, expected_price)
      assert Decimal.equal?(order.quantity, Decimal.new("0.001"))
    end

    test "removes filled order from active orders" do
      {:ok, state} = Grid.init(%{"symbol" => "BTCUSDT"})

      # Add some active orders
      state = %{
        state |
        active_orders: [
          %{order_id: "12345", side: "BUY"},
          %{order_id: "12346", side: "SELL"}
        ]
      }

      execution = %{
        "x" => "TRADE",
        "i" => "12345",
        "S" => "BUY",
        "L" => "49500.00"
      }

      assert {{:place_order, _order}, new_state} = Grid.on_execution(execution, state)

      # Order 12345 should be removed
      assert length(new_state.active_orders) == 1
      assert Enum.all?(new_state.active_orders, fn o -> o.order_id != "12345" end)
    end

    test "ignores non-TRADE executions" do
      {:ok, state} = Grid.init(%{"symbol" => "BTCUSDT"})

      execution = %{
        "x" => "NEW",
        "i" => "12345",
        "S" => "BUY"
      }

      assert {:noop, new_state} = Grid.on_execution(execution, state)
      assert new_state == state
    end
  end

  describe "grid calculation accuracy" do
    test "calculates grid levels with correct spacing" do
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_levels" => 5,
        "grid_spacing" => "0.005"  # 0.5%
      })

      base_price = Decimal.new("50000.00")
      market_data = %{"c" => "50000.00"}

      {{:place_order, orders}, _state} = Grid.on_tick(market_data, state)

      buy_orders = Enum.filter(orders, fn o -> o.side == "BUY" end)
      sell_orders = Enum.filter(orders, fn o -> o.side == "SELL" end)

      # Check buy orders spacing
      sorted_buys = Enum.sort_by(buy_orders, & &1.price, {:desc, Decimal})

      Enum.with_index(sorted_buys, 1)
      |> Enum.each(fn {order, level} ->
        expected = Decimal.mult(
          base_price,
          Decimal.sub(Decimal.new("1"), Decimal.mult(Decimal.new("0.005"), level))
        )
        assert Decimal.equal?(order.price, expected)
      end)

      # Check sell orders spacing
      sorted_sells = Enum.sort_by(sell_orders, & &1.price, {:asc, Decimal})

      Enum.with_index(sorted_sells, 1)
      |> Enum.each(fn {order, level} ->
        expected = Decimal.mult(
          base_price,
          Decimal.add(Decimal.new("1"), Decimal.mult(Decimal.new("0.005"), level))
        )
        assert Decimal.equal?(order.price, expected)
      end)
    end
  end

  describe "complete grid trading cycle" do
    test "executes full rebalancing cycle" do
      # Initialize grid
      {:ok, state} = Grid.init(%{
        "symbol" => "BTCUSDT",
        "grid_levels" => 2,
        "grid_spacing" => "0.01",
        "quantity_per_grid" => "0.001"
      })

      # Step 1: Initialize grid
      market_data = %{"c" => "50000.00"}
      {{:place_order, initial_orders}, state} = Grid.on_tick(market_data, state)
      assert length(initial_orders) == 4  # 2 buy + 2 sell

      # Step 2: Buy order fills at 49500
      buy_execution = %{
        "x" => "TRADE",
        "i" => "order_1",
        "S" => "BUY",
        "L" => "49500.00"
      }
      {{:place_order, sell_order}, state} = Grid.on_execution(buy_execution, state)
      assert sell_order.side == "SELL"
      assert Decimal.equal?(sell_order.price, Decimal.mult(Decimal.new("49500.00"), Decimal.new("1.01")))

      # Step 3: Sell order fills at 50000
      sell_execution = %{
        "x" => "TRADE",
        "i" => "order_2",
        "S" => "SELL",
        "L" => "50000.00"
      }
      {{:place_order, buy_order}, state} = Grid.on_execution(sell_execution, state)
      assert buy_order.side == "BUY"
      assert Decimal.equal?(buy_order.price, Decimal.mult(Decimal.new("50000.00"), Decimal.new("0.99")))
    end
  end
end
