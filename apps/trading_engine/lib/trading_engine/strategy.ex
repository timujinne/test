defmodule TradingEngine.Strategy do
  @moduledoc """
  Behaviour for trading strategies.
  
  All strategies must implement these callbacks.
  """

  @type state :: any()
  @type config :: map()
  @type market_data :: map()
  @type execution :: map()
  @type action :: {:place_order, map()} | {:cancel_order, String.t()} | :noop

  @callback init(config) :: {:ok, state}
  @callback on_tick(market_data, state) :: {action, state}
  @callback on_execution(execution, state) :: {action, state}
end
