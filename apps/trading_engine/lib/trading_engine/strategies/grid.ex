defmodule TradingEngine.Strategies.Grid do
  @moduledoc """
  Grid trading strategy implementation.

  Grid trading involves placing buy and sell orders at regular intervals
  around a base price to profit from market volatility.

  ## Strategy Parameters:
  - Grid levels: Number of price levels in the grid
  - Grid spacing: Percentage distance between each level
  - Order size: Quantity per order
  - Price range: Upper and lower bounds for the grid

  ## How it works:
  1. Establish a price range (upper and lower bounds)
  2. Divide the range into equal intervals (grid levels)
  3. Place buy orders at each level below current price
  4. Place sell orders at each level above current price
  5. When a buy order fills, place a sell order one level above
  6. When a sell order fills, place a buy order one level below

  This is particularly effective in ranging/sideways markets.
  """

  require Logger

  defstruct [
    :symbol,
    :grid_levels,
    :grid_spacing_percent,
    :order_size,
    :base_price,
    :upper_bound,
    :lower_bound,
    :active_orders
  ]

  @default_grid_levels 10
  @default_grid_spacing 1.0
  @default_order_size_percent 10.0

  @doc """
  Initialize a new grid strategy.

  ## Options:
  - `:symbol` - Trading pair (e.g., "BTCUSDT")
  - `:grid_levels` - Number of grid levels (default: 10)
  - `:grid_spacing_percent` - Spacing between levels as percentage (default: 1.0%)
  - `:order_size_percent` - Percentage of balance per order (default: 10%)
  - `:base_price` - Center price for the grid
  """
  def new(opts) do
    symbol = Keyword.fetch!(opts, :symbol)
    base_price = Keyword.fetch!(opts, :base_price)
    grid_levels = Keyword.get(opts, :grid_levels, @default_grid_levels)
    grid_spacing = Keyword.get(opts, :grid_spacing_percent, @default_grid_spacing)

    # Calculate grid bounds
    range_percent = grid_levels * grid_spacing / 2
    upper_bound = base_price * (1 + range_percent / 100)
    lower_bound = base_price * (1 - range_percent / 100)

    %__MODULE__{
      symbol: symbol,
      grid_levels: grid_levels,
      grid_spacing_percent: grid_spacing,
      order_size: nil,
      base_price: base_price,
      upper_bound: upper_bound,
      lower_bound: lower_bound,
      active_orders: %{}
    }
  end

  @doc """
  Calculate grid levels and generate initial orders.
  """
  def calculate_grid_levels(%__MODULE__{} = grid) do
    price_step = (grid.upper_bound - grid.lower_bound) / grid.grid_levels

    levels =
      for i <- 0..grid.grid_levels do
        price = grid.lower_bound + i * price_step
        side = if price < grid.base_price, do: :buy, else: :sell

        %{
          level: i,
          price: price,
          side: side,
          filled: false
        }
      end

    {grid, levels}
  end

  @doc """
  Evaluate the grid strategy based on current price and filled orders.

  Returns list of orders to place: [{:buy, price, quantity}, {:sell, price, quantity}, ...]
  """
  def evaluate(%__MODULE__{} = grid, current_price, balance) do
    # Calculate order size if not set
    order_size = grid.order_size || calculate_order_size(balance, grid.grid_levels)

    # Get current grid levels
    {_grid, levels} = calculate_grid_levels(grid)

    # Determine which orders need to be placed
    orders_to_place =
      levels
      |> Enum.filter(fn level ->
        # Place buy orders below current price
        # Place sell orders above current price
        (level.side == :buy and level.price < current_price) or
          (level.side == :sell and level.price > current_price)
      end)
      |> Enum.reject(fn level ->
        # Don't place orders that are already active
        Map.has_key?(grid.active_orders, level.level)
      end)
      |> Enum.map(fn level ->
        {level.side, level.price, order_size, level.level}
      end)

    Logger.info("""
    [Grid] Evaluated for #{grid.symbol}:
    - Current price: #{current_price}
    - Grid range: #{grid.lower_bound} - #{grid.upper_bound}
    - Orders to place: #{length(orders_to_place)}
    """)

    orders_to_place
  end

  @doc """
  Handle a filled order and determine the next order to place.
  """
  def handle_filled_order(%__MODULE__{} = grid, filled_level, filled_side) do
    # When a buy order fills, place a sell order one level above
    # When a sell order fills, place a buy order one level below
    next_level =
      case filled_side do
        :buy -> filled_level + 1
        :sell -> filled_level - 1
      end

    {_grid, levels} = calculate_grid_levels(grid)
    next_level_data = Enum.find(levels, fn l -> l.level == next_level end)

    case next_level_data do
      nil ->
        # No next level (edge of grid reached)
        Logger.info("[Grid] Edge of grid reached at level #{filled_level}")
        nil

      level ->
        # Place opposite order at next level
        opposite_side = if filled_side == :buy, do: :sell, else: :buy
        {opposite_side, level.price, grid.order_size, level.level}
    end
  end

  @doc """
  Update grid with new active order.
  """
  def add_active_order(%__MODULE__{} = grid, level, order_id) do
    active_orders = Map.put(grid.active_orders, level, order_id)
    %{grid | active_orders: active_orders}
  end

  @doc """
  Remove filled order from active orders.
  """
  def remove_active_order(%__MODULE__{} = grid, level) do
    active_orders = Map.delete(grid.active_orders, level)
    %{grid | active_orders: active_orders}
  end

  # Private functions

  defp calculate_order_size(balance, grid_levels) when is_number(balance) do
    # Use @default_order_size_percent of balance per order
    # Divided by grid levels to ensure we don't over-allocate
    balance * @default_order_size_percent / 100 / grid_levels
  end

  defp calculate_order_size(_balance, _grid_levels), do: 0

  @doc """
  Check if price is within grid bounds.
  """
  def within_bounds?(%__MODULE__{} = grid, price) do
    price >= grid.lower_bound and price <= grid.upper_bound
  end

  @doc """
  Adjust grid based on market movement (rebalance).
  """
  def rebalance(%__MODULE__{} = grid, new_base_price) do
    %{grid | base_price: new_base_price}
    |> recalculate_bounds()
  end

  defp recalculate_bounds(%__MODULE__{} = grid) do
    range_percent = grid.grid_levels * grid.grid_spacing_percent / 2
    upper_bound = grid.base_price * (1 + range_percent / 100)
    lower_bound = grid.base_price * (1 - range_percent / 100)

    %{grid | upper_bound: upper_bound, lower_bound: lower_bound}
  end
end
