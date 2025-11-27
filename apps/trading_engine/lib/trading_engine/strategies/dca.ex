defmodule TradingEngine.Strategies.DCA do
  @moduledoc """
  Dollar Cost Averaging (DCA) strategy.

  Buys a fixed USDT amount at regular intervals using timer-based execution.
  Uses the Trader's timer system instead of polling ticks for time checks.

  ## Features
  - Timer-based execution: Efficient, no tick polling
  - Fetches price via API when timer fires
  - Optional tick subscription for price-based stop conditions
  """
  @behaviour TradingEngine.Strategy

  require Logger

  alias DataCollector.BinanceClient

  @impl true
  def requirements(config) do
    # Calculate interval from config
    interval_ms = cond do
      config["interval_hours"] -> trunc(config["interval_hours"] * 3_600_000)
      config["interval_minutes"] -> config["interval_minutes"] * 60_000
      config["interval_ms"] -> config["interval_ms"]
      true -> 3_600_000
    end

    # Check if there are price-based stop conditions that require tick subscription
    has_price_conditions = has_price_based_stop_conditions?(config)

    %{
      ticks: has_price_conditions,  # Only subscribe to ticks if needed for stop conditions
      timers: [interval_ms],         # Timer for periodic DCA buys
      executions: true
    }
  end

  # Check if config has stop conditions that depend on price
  defp has_price_based_stop_conditions?(config) do
    stop_conditions = config["stop_conditions"] || []

    Enum.any?(stop_conditions, fn condition ->
      case condition do
        %{"type" => type} when type in ["stop_loss", "take_profit", "trailing_stop"] -> true
        _ -> false
      end
    end)
  end

  @impl true
  def init(config) do
    # Support different config field names from UI
    amount = config["amount_per_buy"] || config["investment_amount"] || config["trade_amount"] || 10

    # Support various interval formats
    interval_ms = cond do
      config["interval_hours"] -> trunc(config["interval_hours"] * 3_600_000)
      config["interval_minutes"] -> config["interval_minutes"] * 60_000
      config["interval_ms"] -> config["interval_ms"]
      true -> 3_600_000  # default 1 hour
    end

    max_buys = config["max_buys"] || 999

    state = %{
      symbol: config["symbol"],
      investment_amount: to_decimal(amount, "10"),
      interval_ms: interval_ms,
      max_buys: trunc(max_buys),
      total_invested: Decimal.new(0),
      total_quantity: Decimal.new(0),
      buy_count: 0,
      last_price: nil,  # Cached from ticks or API
      stop_conditions: config["stop_conditions"] || []
    }

    interval_sec = div(interval_ms, 1000)
    Logger.info("DCA: Initialized for #{state.symbol}, amount=#{state.investment_amount} USDT, interval=#{interval_sec}s, max_buys=#{state.max_buys}")

    {:ok, state}
  end

  # Convert various types to Decimal safely
  defp to_decimal(nil, default), do: Decimal.new(default)
  defp to_decimal(value, _default) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(%Decimal{} = value, _default), do: value

  @doc """
  Timer-based execution - called at each DCA interval.
  Fetches current price via API and places buy order.
  """
  @impl true
  def on_timer(_ref, state) do
    if state.buy_count >= state.max_buys do
      Logger.info("DCA: Max buys reached (#{state.buy_count}/#{state.max_buys}), skipping")
      {:noop, state}
    else
      # Fetch current price via API (more reliable than cached tick)
      case get_current_price(state.symbol) do
        {:ok, current_price} ->
          {_price_prec, qty_prec} = get_symbol_precision(state.symbol)
          quantity = Decimal.div(state.investment_amount, current_price) |> Decimal.round(qty_prec)

          Logger.info("DCA: Timer fired - Buying #{quantity} #{state.symbol} for #{state.investment_amount} USDT at #{current_price} (buy ##{state.buy_count + 1})")

          action = {:place_order, %{
            symbol: state.symbol,
            side: "BUY",
            type: "MARKET",
            quantity: quantity
          }}

          {action, state}

        {:error, reason} ->
          Logger.error("DCA: Failed to fetch price for #{state.symbol}: #{inspect(reason)}")
          {:noop, state}
      end
    end
  end

  @doc """
  Tick handler - only called if strategy has price-based stop conditions.
  Updates cached price and checks stop conditions.
  """
  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])
    new_state = %{state | last_price: current_price}

    # Check stop conditions if any exist
    case check_stop_conditions(current_price, new_state) do
      {:stop, reason} ->
        Logger.info("DCA: Stop condition triggered - #{reason}")
        # Could trigger a sell or notify, for now just log
        {:noop, new_state}

      :continue ->
        {:noop, new_state}
    end
  end

  @impl true
  def on_execution(%{"x" => "TRADE", "S" => "BUY"} = execution, state) do
    price = Decimal.new(execution["L"])
    qty = Decimal.new(execution["l"])
    cost = Decimal.mult(price, qty)

    new_state = %{state |
      total_invested: Decimal.add(state.total_invested, cost),
      total_quantity: Decimal.add(state.total_quantity, qty),
      buy_count: state.buy_count + 1,
      last_price: price
    }

    avg_price = if Decimal.gt?(new_state.total_quantity, Decimal.new(0)) do
      Decimal.div(new_state.total_invested, new_state.total_quantity) |> Decimal.round(4)
    else
      Decimal.new(0)
    end

    Logger.info("DCA: Bought #{qty} at #{price}. Total: #{new_state.total_quantity}, Avg price: #{avg_price}, Buy count: #{new_state.buy_count}/#{new_state.max_buys}")

    {:noop, new_state}
  end

  @impl true
  def on_execution(_execution, state) do
    {:noop, state}
  end

  # Private functions

  defp get_current_price(symbol) do
    case BinanceClient.get_ticker_price(symbol) do
      {:ok, %{"price" => price_str}} ->
        {:ok, Decimal.new(price_str)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_stop_conditions(_current_price, %{stop_conditions: []}) do
    :continue
  end

  defp check_stop_conditions(current_price, state) do
    avg_price = if Decimal.gt?(state.total_quantity, Decimal.new(0)) do
      Decimal.div(state.total_invested, state.total_quantity)
    else
      nil
    end

    # Check each stop condition
    result = Enum.find_value(state.stop_conditions, :continue, fn condition ->
      check_single_condition(condition, current_price, avg_price)
    end)

    result
  end

  defp check_single_condition(%{"type" => "stop_loss", "percentage" => pct}, current_price, avg_price)
       when not is_nil(avg_price) do
    threshold = Decimal.mult(avg_price, Decimal.sub(1, Decimal.div(Decimal.new(pct), 100)))
    if Decimal.lt?(current_price, threshold) do
      {:stop, "Stop loss triggered at #{current_price} (threshold: #{threshold})"}
    else
      nil
    end
  end

  defp check_single_condition(%{"type" => "take_profit", "percentage" => pct}, current_price, avg_price)
       when not is_nil(avg_price) do
    threshold = Decimal.mult(avg_price, Decimal.add(1, Decimal.div(Decimal.new(pct), 100)))
    if Decimal.gt?(current_price, threshold) do
      {:stop, "Take profit triggered at #{current_price} (threshold: #{threshold})"}
    else
      nil
    end
  end

  defp check_single_condition(_, _, _), do: nil

  # Symbol precision for price and quantity
  defp get_symbol_precision(symbol) do
    case symbol do
      "BTCUSDT" -> {2, 5}
      "ETHUSDT" -> {2, 4}
      "DOGEUSDT" -> {5, 0}
      "SOLUSDT" -> {2, 2}
      "DOTUSDT" -> {3, 2}
      _ -> {5, 2}
    end
  end
end
