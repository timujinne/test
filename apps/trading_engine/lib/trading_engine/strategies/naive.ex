defmodule TradingEngine.Strategies.Naive do
  @moduledoc """
  Naive buy-low, sell-high strategy.
  
  Buys when price drops by X% and sells when price rises by Y%.
  Simple strategy for testing purposes.
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def requirements(_config) do
    # Naive strategy needs ticks to detect price movements for buy/sell signals
    %{
      ticks: true,
      timers: [],
      executions: true
    }
  end

  @impl true
  def init(config) do
    # trade_amount is in USDT - we'll calculate quantity at order time
    trade_amount_usdt = config["trade_amount"] || config["quantity"] || 10

    # buy_threshold is negative percentage (e.g., -1.2 means buy when price drops 1.2%)
    buy_interval = config["buy_down_interval"] ||
      (config["buy_threshold"] && abs(config["buy_threshold"]) / 100)

    # sell_threshold is positive percentage (e.g., 2.2 means sell when price rises 2.2%)
    sell_interval = config["sell_up_interval"] ||
      (config["sell_threshold"] && config["sell_threshold"] / 100)

    state = %{
      symbol: config["symbol"],
      buy_down_interval: to_decimal(buy_interval, "0.01"),
      sell_up_interval: to_decimal(sell_interval, "0.01"),
      trade_amount_usdt: to_decimal(trade_amount_usdt, "10"),
      last_price: nil,
      position: nil
    }

    Logger.info("Naive: Initialized for #{state.symbol} with trade_amount=#{state.trade_amount_usdt} USDT, buy_down=#{Decimal.mult(state.buy_down_interval, 100)}%, sell_up=#{Decimal.mult(state.sell_up_interval, 100)}%")

    {:ok, state}
  end

  # Convert various types to Decimal safely
  defp to_decimal(nil, default), do: Decimal.new(default)
  defp to_decimal(value, _default) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(%Decimal{} = value, _default), do: value

  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])

    action = cond do
      # No position - check if we should buy
      state.position == nil and should_buy?(current_price, state) ->
        # Calculate quantity from USDT amount
        {_price_prec, qty_prec} = get_symbol_precision(state.symbol)
        quantity = Decimal.div(state.trade_amount_usdt, current_price) |> Decimal.round(qty_prec)

        Logger.info("Naive: Buy signal at #{current_price}, quantity=#{quantity} (#{state.trade_amount_usdt} USDT)")
        {:place_order, %{
          symbol: state.symbol,
          side: "BUY",
          type: "MARKET",
          quantity: quantity
        }}

      # Have position - check if we should sell
      state.position != nil and should_sell?(current_price, state) ->
        # Sell the quantity we bought
        Logger.info("Naive: Sell signal at #{current_price}, quantity=#{state.position.quantity}")
        {:place_order, %{
          symbol: state.symbol,
          side: "SELL",
          type: "MARKET",
          quantity: state.position.quantity
        }}

      true ->
        :noop
    end
    
    new_state = %{state | last_price: current_price}
    {action, new_state}
  end

  @impl true
  def on_execution(execution, state) do
    case execution["x"] do  # Execution type
      "TRADE" ->
        side = execution["S"]
        price = Decimal.new(execution["L"])  # Last executed price
        qty = Decimal.new(execution["l"])    # Last executed quantity
        
        new_state = case side do
          "BUY" ->
            Logger.info("Naive: Bought #{qty} at #{price}")
            %{state | position: %{entry_price: price, quantity: qty}}
            
          "SELL" ->
            Logger.info("Naive: Sold #{qty} at #{price}")
            %{state | position: nil}
        end
        
        {:noop, new_state}
        
      _ ->
        {:noop, state}
    end
  end

  # Private functions

  defp should_buy?(_current_price, %{last_price: nil}), do: false
  
  defp should_buy?(current_price, state) do
    price_change = Decimal.div(
      Decimal.sub(current_price, state.last_price),
      state.last_price
    )

    Decimal.compare(price_change, Decimal.negate(state.buy_down_interval)) == :lt
  end

  defp should_sell?(_current_price, %{position: nil}), do: false
  
  defp should_sell?(current_price, state) do
    entry_price = state.position.entry_price

    price_change = Decimal.div(
      Decimal.sub(current_price, entry_price),
      entry_price
    )

    Decimal.compare(price_change, state.sell_up_interval) == :gt
  end

  # Symbol precision for price and quantity
  defp get_symbol_precision(symbol) do
    case symbol do
      "BTCUSDT" -> {2, 5}   # price: 0.01, qty: 0.00001
      "ETHUSDT" -> {2, 4}   # price: 0.01, qty: 0.0001
      "DOGEUSDT" -> {5, 0}  # price: 0.00001, qty: 1
      "SOLUSDT" -> {2, 2}   # price: 0.01, qty: 0.01
      "DOTUSDT" -> {3, 2}   # price: 0.001, qty: 0.01
      _ -> {5, 2}           # default
    end
  end
end
