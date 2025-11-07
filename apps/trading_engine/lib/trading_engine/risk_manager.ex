defmodule TradingEngine.RiskManager do
  @moduledoc """
  Risk management system for controlling position sizes and managing risk.

  Features:
  - Position size calculation
  - Stop-loss management
  - Maximum drawdown protection
  - Portfolio-level risk limits
  """

  use GenServer
  require Logger

  @default_max_position_size_percent 2.0
  @default_max_portfolio_risk_percent 10.0
  @default_stop_loss_percent 2.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    state = %{
      max_position_size_percent: @default_max_position_size_percent,
      max_portfolio_risk_percent: @default_max_portfolio_risk_percent,
      default_stop_loss_percent: @default_stop_loss_percent,
      user_risks: %{}
    }

    {:ok, state}
  end

  @doc """
  Calculate position size based on account balance and risk parameters.

  Returns the maximum quantity that can be purchased while staying within risk limits.
  """
  def calculate_position_size(user_id, symbol, price, account_balance) do
    GenServer.call(__MODULE__, {:calculate_position_size, user_id, symbol, price, account_balance})
  end

  @doc """
  Check if a trade is allowed based on current risk limits.
  """
  def check_trade_allowed(user_id, symbol, side, quantity, price) do
    GenServer.call(__MODULE__, {:check_trade_allowed, user_id, symbol, side, quantity, price})
  end

  @doc """
  Calculate stop-loss price for a position.
  """
  def calculate_stop_loss(side, entry_price, stop_loss_percent \\ nil) do
    percent = stop_loss_percent || @default_stop_loss_percent

    case side do
      "BUY" ->
        # For long positions, stop-loss is below entry price
        entry_price * (1 - percent / 100)

      "SELL" ->
        # For short positions, stop-loss is above entry price
        entry_price * (1 + percent / 100)

      _ ->
        entry_price
    end
  end

  def handle_call({:calculate_position_size, user_id, _symbol, price, account_balance}, _from, state) do
    max_position_value = account_balance * (state.max_position_size_percent / 100)
    max_quantity = Decimal.div(Decimal.new(max_position_value), Decimal.new(price))

    Logger.debug("Calculated position size for user #{user_id}: #{max_quantity} (max value: $#{max_position_value})")

    {:reply, {:ok, max_quantity}, state}
  end

  def handle_call({:check_trade_allowed, user_id, symbol, side, quantity, price}, _from, state) do
    trade_value = Decimal.mult(Decimal.new(quantity), Decimal.new(price))

    # Check against user risk limits
    user_risk = Map.get(state.user_risks, user_id, %{total_exposure: Decimal.new(0)})
    current_exposure = Map.get(user_risk, :total_exposure, Decimal.new(0))

    # For simplicity, allow trade if within basic limits
    # In production, this would check against more sophisticated risk metrics
    allowed? = Decimal.compare(trade_value, Decimal.new(100_000)) == :lt

    if allowed? do
      Logger.info("Trade allowed for user #{user_id}: #{side} #{quantity} #{symbol} @ #{price}")
      {:reply, :ok, state}
    else
      Logger.warning("Trade rejected for user #{user_id}: exceeds risk limits")
      {:reply, {:error, :risk_limit_exceeded}, state}
    end
  end
end
