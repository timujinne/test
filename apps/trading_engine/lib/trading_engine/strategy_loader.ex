defmodule TradingEngine.StrategyLoader do
  @moduledoc """
  Maps strategy names to their implementation modules.
  """

  @strategies %{
    "naive" => TradingEngine.Strategies.Naive,
    "grid" => TradingEngine.Strategies.Grid,
    "dca" => TradingEngine.Strategies.DCA
  }

  @doc """
  Returns the strategy module for a given strategy name.
  Raises if strategy is unknown.
  """
  @spec get_strategy_module(String.t()) :: module()
  def get_strategy_module(name) when is_binary(name) do
    case Map.get(@strategies, name) do
      nil -> raise ArgumentError, "Unknown strategy: #{name}"
      module -> module
    end
  end

  @doc """
  Returns a list of available strategy names.
  """
  @spec available_strategies() :: [String.t()]
  def available_strategies do
    Map.keys(@strategies)
  end

  @doc """
  Checks if a strategy name is valid.
  """
  @spec valid_strategy?(String.t()) :: boolean()
  def valid_strategy?(name) when is_binary(name) do
    Map.has_key?(@strategies, name)
  end

  @doc """
  Registers a new strategy dynamically.
  Useful for testing or runtime extensions.
  """
  @spec register_strategy(String.t(), module()) :: :ok
  def register_strategy(name, module) when is_binary(name) and is_atom(module) do
    # Note: This modifies module attribute at runtime, won't persist across restarts
    # For production use, strategies should be defined at compile time
    :persistent_term.put({__MODULE__, :custom_strategies, name}, module)
    :ok
  end

  @doc """
  Gets a strategy module, checking custom strategies first.
  """
  @spec get_strategy_module_safe(String.t()) :: {:ok, module()} | {:error, :unknown_strategy}
  def get_strategy_module_safe(name) when is_binary(name) do
    # Check custom strategies first
    case :persistent_term.get({__MODULE__, :custom_strategies, name}, nil) do
      nil ->
        case Map.get(@strategies, name) do
          nil -> {:error, :unknown_strategy}
          module -> {:ok, module}
        end

      module ->
        {:ok, module}
    end
  end
end
