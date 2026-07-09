defmodule DataCollector.OKX.Symbols do
  @moduledoc """
  Caches the mapping between Binance-style concat symbols (`"BTCUSDT"`) and
  OKX `instId` symbols (`"BTC-USDT"`), plus per-symbol precision/size info
  (`tick_sz`/`lot_sz`/`min_sz`), sourced from `GET /api/v5/public/instruments`
  (public, unauthenticated).

  OKX has no per-symbol instrument lookup endpoint, so unlike
  `TradingEngine.SymbolInfo` (which fetches one symbol at a time from
  Binance), this module fetches the *entire* SPOT instrument list in one
  call and caches all of it. Both lookup directions and the size/precision
  map live in a single public ETS table, following the same
  GenServer-owns-a-public-ETS-table pattern as `TradingEngine.SymbolInfo`.

  The instrument list is lazily loaded on the first lookup (nothing is
  fetched at application boot). If a lookup misses after the cache has
  already been loaded once, one refresh is attempted (covers a symbol newly
  listed on OKX since the last load) before giving up with
  `{:error, :unknown_symbol}`.
  """

  use GenServer
  require Logger

  alias SharedData.Config

  @table :okx_symbols_cache

  @type instrument_info :: %{
          tick_sz: String.t(),
          lot_sz: String.t(),
          min_sz: String.t()
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Binance-style concat symbol (`"BTCUSDT"`) -> OKX `instId` (`"BTC-USDT"`).
  """
  @spec to_inst_id(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_inst_id(concat) when is_binary(concat) do
    lookup({:concat, concat})
  end

  @doc """
  OKX `instId` (`"BTC-USDT"`) -> Binance-style concat symbol (`"BTCUSDT"`).
  """
  @spec to_concat(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_concat(inst_id) when is_binary(inst_id) do
    lookup({:inst_id, inst_id})
  end

  @doc """
  Precision/size info for a symbol, given as a Binance-style concat symbol.
  """
  @spec instrument_info(String.t()) :: {:ok, instrument_info()} | {:error, :unknown_symbol}
  def instrument_info(concat) when is_binary(concat) do
    lookup({:info, concat})
  end

  defp lookup(key) do
    case safe_ets_lookup(key) do
      {:ok, value} -> {:ok, value}
      :miss -> GenServer.call(__MODULE__, {:lookup, key}, Config.timeout(:api))
    end
  end

  defp safe_ets_lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{loaded?: false}}
  end

  @impl true
  def handle_call({:lookup, key}, _from, state) do
    already_loaded? = state.loaded?
    state = if already_loaded?, do: state, else: refresh(state)

    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        {:reply, {:ok, value}, state}

      [] when already_loaded? ->
        # Cache was already warm but this symbol wasn't in it — refresh once
        # in case it was newly listed on OKX, then give up if still missing.
        state = refresh(state)

        case :ets.lookup(@table, key) do
          [{^key, value}] -> {:reply, {:ok, value}, state}
          [] -> {:reply, {:error, :unknown_symbol}, state}
        end

      [] ->
        {:reply, {:error, :unknown_symbol}, state}
    end
  end

  defp refresh(state) do
    case fetch_instruments() do
      {:ok, body} ->
        entries = parse_instruments(body)
        Enum.each(entries, &cache_entry/1)
        Logger.info("DataCollector.OKX.Symbols: cached #{length(entries)} SPOT instruments")
        %{state | loaded?: true}

      {:error, reason} ->
        Logger.warning(
          "DataCollector.OKX.Symbols: failed to fetch instrument list: #{inspect(reason)}"
        )

        state
    end
  end

  defp cache_entry({concat, inst_id, info}) do
    :ets.insert(@table, {{:concat, concat}, inst_id})
    :ets.insert(@table, {{:inst_id, inst_id}, concat})
    :ets.insert(@table, {{:info, concat}, info})
  end

  @doc false
  # Pure parsing of the (already JSON-decoded) OKX instruments response body
  # into `{concat, inst_id, instrument_info}` tuples. No HTTP involved — kept
  # separate from `fetch_instruments/0` so it can be unit-tested directly
  # against a canned fixture.
  @spec parse_instruments(map()) :: [{String.t(), String.t(), instrument_info()}]
  def parse_instruments(%{"data" => data}) when is_list(data) do
    data
    |> Enum.filter(&(&1["state"] == "live"))
    |> Enum.flat_map(&parse_instrument/1)
  end

  def parse_instruments(_other), do: []

  defp parse_instrument(%{
         "instId" => inst_id,
         "baseCcy" => base_ccy,
         "quoteCcy" => quote_ccy,
         "tickSz" => tick_sz,
         "lotSz" => lot_sz,
         "minSz" => min_sz
       })
       when is_binary(inst_id) and base_ccy not in [nil, ""] and quote_ccy not in [nil, ""] do
    concat = base_ccy <> quote_ccy
    [{concat, inst_id, %{tick_sz: tick_sz, lot_sz: lot_sz, min_sz: min_sz}}]
  end

  defp parse_instrument(_other), do: []

  defp fetch_instruments do
    config = Application.get_env(:data_collector, :okx, [])
    base_url = Keyword.get(config, :base_url, "https://www.okx.com")
    demo? = Keyword.get(config, :demo, false)
    headers = if demo?, do: [{"x-simulated-trading", "1"}], else: []

    DataCollector.CircuitBreaker.call(:okx_api, fn ->
      case HTTPoison.get(
             "#{base_url}/api/v5/public/instruments",
             headers,
             params: %{instType: "SPOT"}
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status_code: status, body: body}} ->
          {:error, "HTTP #{status}: #{body}"}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
end
