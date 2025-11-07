---
name: elixir-testing
description: Testing strategies for Elixir applications including unit tests, integration tests, and mocking. Use when writing tests for GenServers, supervision trees, or API integrations.
---

# Elixir Testing Strategies

## ExUnit Basics

```elixir
defmodule MyApp.TraderTest do
  use ExUnit.Case, async: true
  
  test "calculates buy price correctly" do
    current_price = Decimal.new("45000")
    buy_down_interval = Decimal.new("0.02")
    
    result = Trader.calculate_buy_price(current_price, buy_down_interval)
    
    assert Decimal.equal?(result, Decimal.new("44100"))
  end
end
```

## Mocking with Mox

```elixir
# test/test_helper.exs
Mox.defmock(BinanceClientMock, for: BinanceClient)

# test
test "places order successfully" do
  expect(BinanceClientMock, :place_order, fn _symbol, _side, _params ->
    {:ok, %{order_id: 123, status: "FILLED"}}
  end)
  
  assert {:ok, _} = Trader.place_buy_order("BTCUSDT", "0.001")
end
```

## Testing GenServers

```elixir
test "trader state machine transitions correctly" do
  {:ok, pid} = Trader.start_link(%{symbol: "BTCUSDT", budget: 100})
  
  # Simulate price update
  send(pid, %TradeEvent{price: "45000"})
  
  # Assert state changed
  state = :sys.get_state(pid)
  assert state.state == :waiting_buy_fill
end
```
