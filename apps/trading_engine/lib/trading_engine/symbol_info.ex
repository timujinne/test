defmodule TradingEngine.SymbolInfo do
  @moduledoc """
  Caches information about trading pairs (precision for price and quantity).
  Loads data from Binance API on first request.
  """
  use GenServer
  require Logger

  @table :symbol_info_cache

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get precision for symbol.
  Returns {price_precision, qty_precision}.
  """
  def get_precision(symbol) do
    case :ets.lookup(@table, symbol) do
      [{^symbol, precision}] -> precision
      [] -> GenServer.call(__MODULE__, {:fetch_precision, symbol})
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:fetch_precision, symbol}, _from, state) do
    precision = fetch_and_cache(symbol)
    {:reply, precision, state}
  end

  defp fetch_and_cache(symbol) do
    case DataCollector.BinanceClient.get_exchange_info(symbol) do
      {:ok, info} ->
        precision = extract_precision(info)
        :ets.insert(@table, {symbol, precision})
        Logger.info("Cached precision for #{symbol}: #{inspect(precision)}")
        precision

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch precision for #{symbol}: #{inspect(reason)}, using defaults"
        )

        {5, 2}
    end
  end

  defp extract_precision(info) do
    # Handle both exchange info formats: full response or single symbol
    symbol_info = case info do
      %{"symbols" => [first | _]} -> first
      %{"symbols" => symbols} when is_list(symbols) -> List.first(symbols)
      symbol_map when is_map(symbol_map) -> symbol_map
      _ -> %{}
    end

    filters = symbol_info["filters"] || []

    price_filter = Enum.find(filters, fn f -> f["filterType"] == "PRICE_FILTER" end)
    lot_filter = Enum.find(filters, fn f -> f["filterType"] == "LOT_SIZE" end)

    price_precision =
      if price_filter do
        tick_size = price_filter["tickSize"]
        count_decimals(tick_size)
      else
        5
      end

    qty_precision =
      if lot_filter do
        step_size = lot_filter["stepSize"]
        count_decimals(step_size)
      else
        2
      end

    {price_precision, qty_precision}
  end

  defp count_decimals(str) when is_binary(str) do
    case String.split(str, ".") do
      [_, decimals] ->
        decimals
        |> String.trim_trailing("0")
        |> String.length()

      _ ->
        0
    end
  end
end
