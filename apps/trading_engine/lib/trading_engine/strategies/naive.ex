defmodule TradingEngine.Strategies.Naive do
  @moduledoc """
  Naive buy-low, sell-high strategy.
  
  Buys when price drops by X% and sells when price rises by Y%.
  Simple strategy for testing purposes.
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def init(config) do
    state = %{
      symbol: config["symbol"],
      buy_down_interval: Decimal.new(config["buy_down_interval"] || "0.01"),  # 1%
      sell_up_interval: Decimal.new(config["sell_up_interval"] || "0.01"),     # 1%
      quantity: Decimal.new(config["quantity"] || "0.001"),
      last_price: nil,
      position: nil
    }
    
    {:ok, state}
  end

  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])
    
    action = cond do
      # No position - check if we should buy
      state.position == nil and should_buy?(current_price, state) ->
        Logger.info("Naive: Buy signal at #{current_price}")
        {:place_order, %{
          symbol: state.symbol,
          side: "BUY",
          type: "MARKET",
          quantity: state.quantity
        }}
      
      # Have position - check if we should sell
      state.position != nil and should_sell?(current_price, state) ->
        Logger.info("Naive: Sell signal at #{current_price}")
        {:place_order, %{
          symbol: state.symbol,
          side: "SELL",
          type: "MARKET",
          quantity: state.quantity
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
end
