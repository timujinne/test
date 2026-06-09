defmodule TradingEngine.Conditions.Condition do
  @moduledoc """
  Behaviour for start and stop conditions.

  Conditions evaluate market data and determine whether trading should start or stop.
  Each condition maintains its own state for tracking things like price crossings.
  """

  @type condition_config :: map()
  @type market_data :: map()
  @type state :: map()
  @type condition_type :: :start | :stop

  @doc """
  Initialize the condition with its configuration.
  Returns the initial state for the condition.
  """
  @callback init(condition_config()) :: {:ok, state()} | {:error, term()}

  @doc """
  Evaluate the condition against current market data.
  Returns whether the condition is met and the updated state.
  """
  @callback evaluate(market_data(), state()) :: {boolean(), state()}

  @doc """
  Returns whether this is a start or stop condition.
  """
  @callback type() :: condition_type()

  @doc """
  Returns a human-readable description of the condition.
  """
  @callback describe(state()) :: String.t()

  @optional_callbacks [describe: 1]

  @doc """
  Helper to parse a numeric value from config, handling both string and number inputs.
  """
  def parse_number(value) when is_number(value), do: value

  def parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} ->
        num

      :error ->
        case Integer.parse(value) do
          {num, _} -> num
          :error -> nil
        end
    end
  end

  def parse_number(_), do: nil

  @doc """
  Get current price from market data.
  Binance ticker format uses "c" for current/close price.
  """
  def get_price(market_data) when is_map(market_data) do
    price_str = Map.get(market_data, "c") || Map.get(market_data, :c)

    case price_str do
      nil -> nil
      p when is_number(p) -> Decimal.new(p)
      p when is_binary(p) -> Decimal.new(p)
      _ -> nil
    end
  end

  @doc """
  Get 24h volume from market data.
  Binance ticker format uses "v" for volume.
  """
  def get_volume(market_data) when is_map(market_data) do
    volume_str = Map.get(market_data, "v") || Map.get(market_data, :v)

    case volume_str do
      nil -> nil
      v when is_number(v) -> Decimal.new(v)
      v when is_binary(v) -> Decimal.new(v)
      _ -> nil
    end
  end
end
