---
name: trading-strategies
description: Implementation guide for algorithmic trading strategies in Elixir including Naive, Grid, and Market Making strategies. Use when building trading bots, implementing order management systems, or developing automated trading logic.
---

# Trading Strategies Implementation

## Naive Trading Strategy

```elixir
defmodule Naive.Trader do
  use GenServer

  defstruct [:symbol, :buy_order, :sell_order, :profit_interval, :buy_down_interval, :budget, :state]

  def init(params) do
    Phoenix.PubSub.subscribe(Streamer.PubSub, "trade_events:#{params.symbol}")
    
    {:ok, %__MODULE__{
      symbol: params.symbol,
      profit_interval: Decimal.new(params.profit_interval),  # e.g., "0.005" for 0.5%
      buy_down_interval: Decimal.new(params.buy_down_interval),  # e.g., "0.02" for 2%
      budget: Decimal.new(params.budget),
      state: :placing_buy_order
    }}
  end

  # Step 1: Place buy order
  def handle_info(%TradeEvent{price: price}, %{state: :placing_buy_order} = state) do
    buy_price = calculate_buy_price(price, state.buy_down_interval)
    quantity = Decimal.div(state.budget, buy_price)
    
    {:ok, order} = Binance.order_limit_buy(state.symbol, quantity, buy_price)
    
    {:noreply, %{state | buy_order: order, state: :waiting_buy_fill}}
  end

  # Step 2: Wait for buy fill, then place sell
  def handle_info(%TradeEvent{} = event, %{state: :waiting_buy_fill} = state) do
    if order_filled?(state.buy_order, event) do
      sell_price = Decimal.mult(state.buy_order.price, Decimal.add("1", state.profit_interval))
      {:ok, order} = Binance.order_limit_sell(state.symbol, state.buy_order.quantity, sell_price)
      
      {:noreply, %{state | sell_order: order, state: :waiting_sell_fill}}
    else
      {:noreply, state}
    end
  end

  # Step 3: Complete cycle
  def handle_info(%TradeEvent{} = event, %{state: :waiting_sell_fill} = state) do
    if order_filled?(state.sell_order, event) do
      Logger.info("Trade complete: #{state.symbol}, profit: #{calculate_profit(state)}")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end
end
```

## Grid Trading Strategy

```elixir
defmodule Grid.Strategy do
  def create_grid(base_price, grid_size, num_levels) do
    levels = for i <- 1..num_levels do
      buy_price = Decimal.mult(base_price, Decimal.sub(1, Decimal.mult(grid_size, i)))
      sell_price = Decimal.mult(base_price, Decimal.add(1, Decimal.mult(grid_size, i)))
      {buy_price, sell_price}
    end
    levels
  end

  def place_grid_orders(symbol, grid_levels, quantity_per_level) do
    Enum.each(grid_levels, fn {buy_price, sell_price} ->
      Binance.order_limit_buy(symbol, quantity_per_level, buy_price)
      Binance.order_limit_sell(symbol, quantity_per_level, sell_price)
    end)
  end
end
```
