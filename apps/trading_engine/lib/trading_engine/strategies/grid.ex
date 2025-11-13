defmodule TradingEngine.Strategies.Grid do
  @moduledoc """
  Grid trading strategy.
  
  Creates a grid of buy and sell orders at different price levels.
  Automatically rebalances when orders are filled.
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def init(config) do
    state = %{
      symbol: config["symbol"],
      grid_levels: config["grid_levels"] || 5,
      grid_spacing: Decimal.new(config["grid_spacing"] || "0.005"),  # 0.5%
      quantity_per_grid: Decimal.new(config["quantity_per_grid"] || "0.001"),
      base_price: nil,
      active_orders: []
    }
    
    {:ok, state}
  end

  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])
    
    action = if state.base_price == nil do
      # Initialize grid based on current price
      Logger.info("Grid: Initializing grid at #{current_price}")
      {:place_order, create_grid_orders(current_price, state)}
    else
      :noop
    end
    
    new_state = %{state | base_price: current_price}
    {action, new_state}
  end

  @impl true
  def on_execution(execution, state) do
    case execution["x"] do
      "TRADE" ->
        order_id = execution["i"]
        side = execution["S"]
        price = Decimal.new(execution["L"])
        
        Logger.info("Grid: Order #{order_id} filled (#{side}) at #{price}")
        
        # Remove filled order from active orders
        new_active_orders = Enum.reject(state.active_orders, fn o -> 
          o.order_id == order_id 
        end)
        
        # Place opposite order at the next grid level
        opposite_order = case side do
          "BUY" ->
            # After buy, place sell order above
            sell_price = Decimal.mult(price, Decimal.add(1, state.grid_spacing))
            %{
              symbol: state.symbol,
              side: "SELL",
              type: "LIMIT",
              price: sell_price,
              quantity: state.quantity_per_grid,
              timeInForce: "GTC"
            }
            
          "SELL" ->
            # After sell, place buy order below
            buy_price = Decimal.mult(price, Decimal.sub(1, state.grid_spacing))
            %{
              symbol: state.symbol,
              side: "BUY",
              type: "LIMIT",
              price: buy_price,
              quantity: state.quantity_per_grid,
              timeInForce: "GTC"
            }
        end
        
        new_state = %{state | active_orders: new_active_orders}
        {{:place_order, opposite_order}, new_state}
        
      _ ->
        {:noop, state}
    end
  end

  # Private functions

  defp create_grid_orders(base_price, state) do
    buy_orders = for i <- 1..state.grid_levels do
      price = Decimal.mult(
        base_price,
        Decimal.sub(1, Decimal.mult(state.grid_spacing, i))
      )
      
      %{
        symbol: state.symbol,
        side: "BUY",
        type: "LIMIT",
        price: price,
        quantity: state.quantity_per_grid,
        timeInForce: "GTC"
      }
    end
    
    sell_orders = for i <- 1..state.grid_levels do
      price = Decimal.mult(
        base_price,
        Decimal.add(1, Decimal.mult(state.grid_spacing, i))
      )
      
      %{
        symbol: state.symbol,
        side: "SELL",
        type: "LIMIT",
        price: price,
        quantity: state.quantity_per_grid,
        timeInForce: "GTC"
      }
    end
    
    buy_orders ++ sell_orders
  end
end
