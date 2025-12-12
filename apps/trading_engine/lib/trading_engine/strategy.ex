defmodule TradingEngine.Strategy do
  @moduledoc """
  Behaviour for trading strategies.

  All strategies must implement the core callbacks (init, on_tick, on_execution).
  Optional callbacks (requirements, on_timer) enable advanced lifecycle management.

  ## Requirements Declaration

  Strategies can declare their requirements via `requirements/1`:

  ```elixir
  def requirements(_config) do
    %{
      ticks: true,           # Subscribe to market data ticks
      timers: [60_000],      # Schedule timers (intervals in ms)
      executions: true       # Subscribe to execution reports
    }
  end
  ```

  This allows the Trader to:
  - Skip tick subscriptions for timer-only strategies (like DCA)
  - Set up strategy timers automatically
  - Optimize resource usage by not starting unnecessary streams

  ## Timer-Based Strategies

  Strategies that need periodic execution can implement `on_timer/2`:

  ```elixir
  def on_timer(_ref, state) do
    # Called at each timer interval
    {:place_order, %{...}, state}
  end
  ```
  """

  @type state :: any()
  @type config :: map()
  @type market_data :: map()
  @type execution :: map()
  @type action :: {:place_order, map()} | {:cancel_order, String.t()} | :noop

  @typedoc """
  Strategy requirements declaration.

  - `ticks`: Whether to subscribe to market data ticks (default: true)
  - `timers`: List of timer intervals in milliseconds (default: [])
  - `executions`: Whether to subscribe to execution reports (default: true)
  """
  @type requirements :: %{
          ticks: boolean(),
          timers: [pos_integer()],
          executions: boolean()
        }

  # Required callbacks
  @callback init(config) :: {:ok, state} | {:ok, state, action}
  @callback on_tick(market_data, state) :: {action, state}
  @callback on_execution(execution, state) :: {action, state}

  # Optional callbacks
  @callback requirements(config) :: requirements()
  @callback on_timer(timer_ref :: reference(), state) :: {action, state}
  @callback on_order_placed(order :: map(), state) :: any()
  @callback required_symbols(config) :: [String.t()]

  @optional_callbacks [requirements: 1, on_timer: 2, on_order_placed: 2, required_symbols: 1]

  @doc """
  Default requirements for strategies that don't declare their own.
  Subscribes to ticks and executions, no timers.
  """
  @spec default_requirements() :: requirements()
  def default_requirements do
    %{
      ticks: true,
      timers: [],
      executions: true
    }
  end

  @doc """
  Get requirements for a strategy, using defaults if not declared.
  """
  @spec get_requirements(module(), config()) :: requirements()
  def get_requirements(strategy_module, config) do
    if function_exported?(strategy_module, :requirements, 1) do
      strategy_module.requirements(config)
    else
      default_requirements()
    end
  end

  @doc """
  Get required symbols for a strategy.
  Returns list of symbols the strategy needs to subscribe to.
  Falls back to single symbol from config if callback not implemented.
  """
  @spec get_required_symbols(module(), config()) :: [String.t()]
  def get_required_symbols(strategy_module, config) do
    if function_exported?(strategy_module, :required_symbols, 1) do
      strategy_module.required_symbols(config)
    else
      # Fallback to single symbol from config
      case config["symbol"] || config[:symbol] do
        nil -> []
        symbol -> [symbol]
      end
    end
  end
end
