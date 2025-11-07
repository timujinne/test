---
name: genstage-flow
description: Guide for implementing GenStage and Flow patterns for data processing pipelines in Elixir. Use when building event-driven systems, order prioritization, or high-throughput data processing.
---

# GenStage and Flow Patterns

## Order Prioritization Pipeline

```elixir
# Producer
defmodule OrderProducer do
  use GenStage

  def start_link(initial) do
    GenStage.start_link(__MODULE__, initial, name: __MODULE__)
  end

  def init(state) do
    {:producer, state}
  end

  def handle_demand(demand, state) do
    orders = fetch_pending_orders(demand)
    {:noreply, orders, state}
  end
end

# ProducerConsumer - Prioritization
defmodule OrderPrioritizer do
  use GenStage

  def start_link(_) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:producer_consumer, :ok, subscribe_to: [OrderProducer]}
  end

  def handle_events(orders, _from, state) do
    prioritized = Enum.sort_by(orders, &priority_score/1, :desc)
    {:noreply, prioritized, state}
  end

  defp priority_score(order) do
    order.expected_profit * order.size * urgency_factor(order)
  end
end

# Consumer - Execution
defmodule OrderExecutor do
  use GenStage

  def start_link(_) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:consumer, :ok, subscribe_to: [OrderPrioritizer]}
  end

  def handle_events(orders, _from, state) do
    Enum.each(orders, &execute_order/1)
    {:noreply, [], state}
  end
end
```

## Flow for Parallel Processing

```elixir
alias Experimental.Flow

trades
|> Flow.from_enumerable()
|> Flow.partition()
|> Flow.map(&process_trade/1)
|> Flow.reduce(fn -> %{} end, fn trade, acc ->
  Map.update(acc, trade.symbol, trade.volume, &(&1 + trade.volume))
end)
|> Enum.to_list()
```
