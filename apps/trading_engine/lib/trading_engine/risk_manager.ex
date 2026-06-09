defmodule TradingEngine.RiskManager do
  @moduledoc """
  Risk management module to validate orders before execution.
  """
  require Logger

  alias SharedData.Types
  alias SharedData.Repo
  alias SharedData.Config
  alias SharedData.Schemas.Trade

  import Ecto.Query

  # Risk limits are sourced from SharedData.Config (the centralized source of
  # truth) rather than hardcoded here, so tuning the config actually takes effect.
  # Defaults: max_order_size 0.1 BTC, max_position_size 1.0 BTC, max_daily_loss $1000.
  defp max_order_size, do: to_decimal(Config.risk_limit(:max_order_size_btc))
  defp max_position_size, do: to_decimal(Config.risk_limit(:max_position_size_btc))
  defp max_daily_loss, do: to_decimal(Config.risk_limit(:max_daily_loss_usd))

  @spec check_order(Types.order_params(), map()) :: :ok | {:error, String.t()}
  def check_order(order_params, state) do
    with :ok <- check_order_size(order_params),
         :ok <- check_position_size(order_params, state),
         :ok <- check_daily_loss(state) do
      :ok
    end
  end

  @spec check_order_size(Types.order_params()) :: :ok | {:error, String.t()}
  defp check_order_size(%{quantity: quantity}) do
    qty = to_decimal(quantity)

    cond do
      Decimal.compare(qty, Decimal.new(0)) != :gt ->
        {:error, "Order quantity must be greater than zero (got #{qty})"}

      Decimal.compare(qty, max_order_size()) == :gt ->
        {:error, "Order size exceeds maximum allowed (#{max_order_size()})"}

      true ->
        :ok
    end
  end

  defp check_order_size(_), do: :ok

  @spec check_position_size(Types.order_params(), map()) :: :ok | {:error, String.t()}
  defp check_position_size(%{side: "BUY", quantity: quantity}, state) do
    current_position_size = calculate_position_size(state.positions)
    new_qty = to_decimal(quantity)
    total_size = Decimal.add(current_position_size, new_qty)

    if Decimal.compare(total_size, max_position_size()) == :gt do
      {:error, "Position size would exceed maximum allowed (#{max_position_size()})"}
    else
      :ok
    end
  end

  # SELL orders reduce exposure and are intentionally not position-size limited.
  defp check_position_size(_, _), do: :ok

  @spec check_daily_loss(map()) :: :ok | {:error, String.t()}
  defp check_daily_loss(%{account_id: account_id}) when not is_nil(account_id) do
    daily_loss = calculate_daily_loss(account_id)

    if Decimal.compare(Decimal.abs(daily_loss), max_daily_loss()) == :gt do
      {:error, "Daily loss limit exceeded (#{max_daily_loss()} USDT)"}
    else
      :ok
    end
  end

  defp check_daily_loss(_state), do: :ok

  # Safely coerce config values (float/integer/string/Decimal) to Decimal.
  # Floats are routed through Float.to_string to avoid binary-float artifacts
  # (e.g. Decimal.from_float(0.1) is not exactly 0.1).
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_float(value), do: Decimal.new(Float.to_string(value))
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)

  @doc """
  Calculate total P&L for today's trades for a given account.
  Returns negative value for losses, positive for gains.
  """
  @spec calculate_daily_loss(binary()) :: Decimal.t()
  def calculate_daily_loss(account_id) do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    query =
      from t in Trade,
        where: t.account_id == ^account_id,
        where: t.timestamp >= ^today_start,
        where: not is_nil(t.pnl),
        select: sum(t.pnl)

    case Repo.one(query) do
      nil -> Decimal.new(0)
      pnl -> pnl
    end
  end

  @doc """
  Get risk metrics for an account.
  """
  @spec get_risk_metrics(binary()) :: map()
  def get_risk_metrics(account_id) do
    daily_loss = calculate_daily_loss(account_id)
    daily_loss_remaining = Decimal.sub(max_daily_loss(), Decimal.abs(daily_loss))

    %{
      daily_loss: daily_loss,
      max_daily_loss: max_daily_loss(),
      daily_loss_remaining: Decimal.max(daily_loss_remaining, Decimal.new(0)),
      max_order_size: max_order_size(),
      max_position_size: max_position_size()
    }
  end

  @spec calculate_position_size(map()) :: Decimal.t()
  defp calculate_position_size(positions) do
    Enum.reduce(positions, Decimal.new(0), fn {_symbol, pos}, acc ->
      Decimal.add(acc, pos.quantity || Decimal.new(0))
    end)
  end
end
