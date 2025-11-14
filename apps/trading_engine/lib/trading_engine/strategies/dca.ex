defmodule TradingEngine.Strategies.Dca do
  @moduledoc """
  Dollar Cost Averaging (DCA) strategy.
  
  Buys a fixed amount at regular intervals.
  Optionally averages down when price falls.
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def init(config) do
    state = %{
      symbol: config["symbol"],
      investment_amount: Decimal.new(config["investment_amount"] || "100"),  # USDT
      interval_ms: config["interval_ms"] || 3_600_000,  # 1 hour
      average_down: config["average_down"] || false,
      last_buy_time: nil,
      positions: []
    }
    
    # Schedule first buy
    Process.send_after(self(), :dca_buy, state.interval_ms)
    
    {:ok, state}
  end

  @impl true
  def on_tick(market_data, state) do
    # DCA is timer-based, not price-based
    {:noop, state}
  end

  @impl true
  def on_execution(%{"x" => "TRADE", "S" => "BUY"} = execution, state) do
    price = Decimal.new(execution["L"])
    qty = Decimal.new(execution["l"])

    Logger.info("DCA: Bought #{qty} at #{price}")

    new_position = %{
      entry_price: price,
      quantity: qty,
      timestamp: System.system_time(:millisecond)
    }

    new_state = %{state |
      positions: [new_position | state.positions],
      last_buy_time: System.system_time(:millisecond)
    }

    # Schedule next buy
    Process.send_after(self(), :dca_buy, state.interval_ms)

    {:noop, new_state}
  end

  def on_execution(_execution, state) do
    {:noop, state}
  end

  def handle_info(:dca_buy, state) do
    Logger.info("DCA: Time to buy")
    
    # Calculate how much to buy based on current price
    action = {:place_order, %{
      symbol: state.symbol,
      side: "BUY",
      type: "MARKET",
      quoteOrderQty: state.investment_amount  # Buy for fixed USDT amount
    }}
    
    {action, state}
  end
end
