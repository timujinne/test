defmodule TradingEngine.Conditions.ConditionEvaluator do
  @moduledoc """
  Evaluates multiple conditions with AND/OR logic.

  Config format:
  ```
  %{
    "logic" => "and",  # or "or"
    "conditions" => [
      %{"type" => "price", "operator" => "below", "value" => 50000},
      %{"type" => "time", "start_hour" => 9, "end_hour" => 17},
      %{"type" => "volume", "operator" => "above", "value" => 1000000}
    ]
  }
  ```
  """

  alias TradingEngine.Conditions.{
    PriceCondition,
    TimeCondition,
    VolumeCondition,
    TakeProfitCondition,
    StopLossCondition,
    MaxDailyLossCondition,
    TimeStopCondition
  }

  @condition_modules %{
    # Start conditions
    "price" => PriceCondition,
    "time" => TimeCondition,
    "volume" => VolumeCondition,
    # Stop conditions
    "take_profit" => TakeProfitCondition,
    "stop_loss" => StopLossCondition,
    "max_daily_loss" => MaxDailyLossCondition,
    "time_stop" => TimeStopCondition
  }

  @doc """
  Initialize the evaluator with a conditions config.
  Returns a state map with initialized condition states.
  """
  @spec init(map() | nil) :: {:ok, map()} | {:error, term()}
  def init(nil), do: {:ok, %{logic: "and", conditions: []}}

  def init(config) when is_map(config) do
    logic = config["logic"] || "and"
    conditions_config = config["conditions"] || []

    case init_conditions(conditions_config) do
      {:ok, conditions} ->
        {:ok, %{logic: logic, conditions: conditions}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Evaluate all conditions against market data.
  Returns whether all conditions are met (AND) or any condition is met (OR).
  """
  @spec evaluate(map() | nil, map(), map()) :: {boolean(), map()}
  def evaluate(nil, _market_data, state), do: {true, state}

  def evaluate(_config, _market_data, %{conditions: []} = state), do: {true, state}

  def evaluate(_config, market_data, state) do
    {results, new_conditions} =
      state.conditions
      |> Enum.map_reduce([], fn {type, module, cond_state}, acc ->
        {met?, new_cond_state} = module.evaluate(market_data, cond_state)
        {{met?, type}, acc ++ [{type, module, new_cond_state}]}
      end)

    met? =
      case state.logic do
        "and" -> Enum.all?(results, fn {met, _type} -> met end)
        "or" -> Enum.any?(results, fn {met, _type} -> met end)
        _ -> false
      end

    {met?, %{state | conditions: new_conditions}}
  end

  @doc """
  Check if any conditions are configured.
  """
  @spec has_conditions?(map() | nil) :: boolean()
  def has_conditions?(nil), do: false

  def has_conditions?(%{"conditions" => conditions}) when is_list(conditions),
    do: length(conditions) > 0

  def has_conditions?(_), do: false

  @doc """
  Get human-readable description of all conditions.
  """
  @spec describe(map()) :: String.t()
  def describe(%{conditions: [], logic: _}), do: "No conditions"

  def describe(%{conditions: conditions, logic: logic}) do
    descriptions =
      conditions
      |> Enum.map(fn {_type, module, cond_state} ->
        if function_exported?(module, :describe, 1) do
          module.describe(cond_state)
        else
          "Unknown condition"
        end
      end)

    joiner = if logic == "and", do: " AND ", else: " OR "
    Enum.join(descriptions, joiner)
  end

  # Private functions

  defp init_conditions(conditions_config) do
    conditions_config
    |> Enum.reduce_while({:ok, []}, fn config, {:ok, acc} ->
      type = config["type"]

      case Map.get(@condition_modules, type) do
        nil ->
          {:halt, {:error, {:unknown_condition_type, type}}}

        module ->
          case module.init(config) do
            {:ok, cond_state} ->
              {:cont, {:ok, acc ++ [{type, module, cond_state}]}}

            {:error, reason} ->
              {:halt, {:error, {type, reason}}}
          end
      end
    end)
  end

  @doc """
  Register a custom condition module.
  Useful for extending with new condition types.
  """
  @spec register_condition(String.t(), module()) :: :ok
  def register_condition(type, module) when is_binary(type) and is_atom(module) do
    :persistent_term.put({__MODULE__, :custom_condition, type}, module)
    :ok
  end

  @doc """
  Get condition module by type, checking custom conditions first.
  """
  @spec get_condition_module(String.t()) :: {:ok, module()} | {:error, :unknown_type}
  def get_condition_module(type) when is_binary(type) do
    case :persistent_term.get({__MODULE__, :custom_condition, type}, nil) do
      nil ->
        case Map.get(@condition_modules, type) do
          nil -> {:error, :unknown_type}
          module -> {:ok, module}
        end

      module ->
        {:ok, module}
    end
  end
end
