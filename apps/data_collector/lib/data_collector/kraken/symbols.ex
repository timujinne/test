defmodule DataCollector.Kraken.Symbols do
  @moduledoc """
  Caches the mapping between Binance-style concat symbols (`"BTCUSD"`) and
  Kraken's pair identifiers, plus per-symbol precision/size info, sourced
  from `GET /0/public/AssetPairs` (public, unauthenticated).

  Kraken has **three** different name variants for the same pair (see
  `docs/superpowers/notes/kraken-api-verified.md` §3):

    * **pair id** (internal, X/Z-prefixed, e.g. `"XXBTZUSD"`) — the
      top-level dict key in `AssetPairs`/`Ticker`/`OHLC` REST responses.
    * **altname** (e.g. `"XBTUSD"`) — what's sent as `pair` in
      `AddOrder`/`CancelOrder`/etc, and what comes back in `descr.pair`.
      This is the canonical REST-facing identifier for this adapter.
    * **WebSocket v2 symbol** (e.g. `"BTC/USD"`) — a *different* clean
      namespace that renames `XBT` to `BTC` (and `XDG` to `DOGE`). It is
      **not** the same as the REST `wsname` field, which is the WS **v1**
      format and is wrong for v2 — this module never reads `wsname`.

  The Binance-style concat symbol (`"BTCUSD"`) is derived from `altname`
  by substituting `"XBT" -> "BTC"` and `"XDG" -> "DOGE"` (the only two
  legacy tickers that survive into `altname`); every other asset's
  `altname` already matches its common ticker. The same substitution,
  applied to the `base`/`quote` fields individually (via
  `asset_code_to_ticker/1`) and joined with `"/"`, produces the WS v2
  symbol.

  Same lazy-load/refresh-once-on-miss pattern as `DataCollector.OKX.Symbols`:
  the pair list is loaded on first lookup (nothing fetched at application
  boot), and a cache miss after the cache is already warm triggers exactly
  one refresh attempt (covers a pair newly listed since the last load)
  before giving up with `{:error, :unknown_symbol}`.
  """

  use GenServer
  require Logger

  alias SharedData.Config

  @table :kraken_symbols_cache

  @type instrument_info :: %{
          tick_size: String.t(),
          step_size: String.t(),
          min_qty: String.t()
        }

  # Legacy X/Z namespace-prefixed internal asset codes that Kraken has kept
  # around (live-verified in verified notes §3) -> their prefix-stripped
  # form. Anything not in this table passes through unchanged. This is a
  # literal pattern-match table (never derived from unvalidated external
  # strings) per the project's atom/behavior-from-external-input rule.
  @legacy_prefixes %{
    "XETH" => "ETH",
    "XLTC" => "LTC",
    "XXRP" => "XRP",
    "XXLM" => "XLM",
    "XXMR" => "XMR",
    "XETC" => "ETC",
    "XZEC" => "ZEC",
    "XREP" => "REP",
    "XXBT" => "XBT",
    "XXDG" => "XDG",
    "ZUSD" => "USD",
    "ZEUR" => "EUR",
    "ZGBP" => "GBP",
    "ZJPY" => "JPY",
    "ZCAD" => "CAD"
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Binance-style concat symbol (`"BTCUSD"`) -> Kraken `altname` (`"XBTUSD"`),
  the value to send as `pair` in `AddOrder`/`CancelOrder`/etc.
  """
  @spec to_pair(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_pair(concat) when is_binary(concat) do
    lookup({:pair, concat})
  end

  @doc """
  Kraken `altname` (`"XBTUSD"`, as echoed in `descr.pair`) **or** Kraken
  pair id (`"XXBTZUSD"`, as used for `Ticker`/`OHLC` dict keys) -> the
  Binance-style concat symbol (`"BTCUSD"`). Accepts either input shape
  transparently.
  """
  @spec to_concat(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_concat(id) when is_binary(id) do
    lookup({:concat, id})
  end

  @doc """
  Binance-style concat symbol (`"BTCUSD"`) -> WebSocket v2 symbol
  (`"BTC/USD"`).
  """
  @spec to_ws_symbol(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_ws_symbol(concat) when is_binary(concat) do
    lookup({:ws, concat})
  end

  @doc """
  Precision/size info for a symbol, given as a Binance-style concat symbol.
  """
  @spec instrument_info(String.t()) :: {:ok, instrument_info()} | {:error, :unknown_symbol}
  def instrument_info(concat) when is_binary(concat) do
    lookup({:info, concat})
  end

  @doc """
  Pure, stateless translation of a Kraken **asset** code (as used in
  `Balance`/`BalanceEx` keys, e.g. `"XXBT"`, `"ZUSD"`, `"USDT"`) to a
  common ticker (`"BTC"`, `"USD"`, `"USDT"`). No ETS/GenServer involved —
  used by `DataCollector.Kraken.Normalize.account_response/1` (asset
  codes, not pair codes) and internally by this module to build WS v2
  symbols from `AssetPairs`' `base`/`quote` fields.

  Two-step recipe (verified notes §3): strip a leading `X`/`Z` namespace
  prefix only when the remainder is one of the fixed known legacy codes
  (anything else, e.g. `"USDT"`/`"ADA"`, passes through unchanged), then
  apply the `"XBT" -> "BTC"` / `"XDG" -> "DOGE"` substitution.
  """
  @spec asset_code_to_ticker(String.t()) :: String.t()
  def asset_code_to_ticker(code) when is_binary(code) do
    Map.get(@legacy_prefixes, code, code)
    |> String.replace("XBT", "BTC")
    |> String.replace("XDG", "DOGE")
  end

  defp lookup(key) do
    case safe_ets_lookup(key) do
      {:ok, value} -> {:ok, value}
      :miss -> GenServer.call(__MODULE__, {:lookup, key}, Config.timeout(:api))
    end
  end

  defp safe_ets_lookup(key) do
    ets_lookup_key(key)
  rescue
    ArgumentError -> :miss
  end

  # `{:concat, id}` tries both the altname and pair-id namespaces (see
  # `to_concat/1`'s moduledoc); every other key is a direct lookup.
  defp ets_lookup_key({:concat, id}) do
    case :ets.lookup(@table, {:altname, id}) do
      [{_, concat}] -> {:ok, concat}
      [] -> ets_lookup_key({:pair_id, id})
    end
  end

  defp ets_lookup_key(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :miss
    end
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

    case ets_lookup_key(key) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}

      :miss when already_loaded? ->
        # Cache was already warm but this symbol wasn't in it — refresh
        # once in case it was newly listed on Kraken, then give up if
        # still missing.
        state = refresh(state)

        case ets_lookup_key(key) do
          {:ok, value} -> {:reply, {:ok, value}, state}
          :miss -> {:reply, {:error, :unknown_symbol}, state}
        end

      :miss ->
        {:reply, {:error, :unknown_symbol}, state}
    end
  end

  defp refresh(state) do
    case fetch_instruments() do
      {:ok, body} ->
        entries = parse_instruments(body)
        Enum.each(entries, &cache_entry/1)
        Logger.info("DataCollector.Kraken.Symbols: cached #{length(entries)} online asset pairs")
        %{state | loaded?: true}

      {:error, reason} ->
        Logger.warning(
          "DataCollector.Kraken.Symbols: failed to fetch asset pairs: #{inspect(reason)}"
        )

        state
    end
  end

  @doc false
  # Inserts one parsed `AssetPairs` entry (as returned by `parse_instruments/1`)
  # into the cache table. Public (but `@doc false`) so tests can seed the
  # cache directly from a canned fixture via `parse_instruments/1` without
  # a live HTTP call — same "factor it out for testability" rationale as
  # `parse_instruments/1` itself.
  @spec cache_entry({String.t(), String.t(), String.t(), String.t(), instrument_info()}) :: true
  def cache_entry({concat, altname, pair_id, ws_symbol, info}) do
    :ets.insert(@table, {{:pair, concat}, altname})
    :ets.insert(@table, {{:altname, altname}, concat})
    :ets.insert(@table, {{:pair_id, pair_id}, concat})
    :ets.insert(@table, {{:ws, concat}, ws_symbol})
    :ets.insert(@table, {{:info, concat}, info})
  end

  @doc false
  # Pure parsing of the (already JSON-decoded) `AssetPairs` envelope
  # (`%{"error" => [], "result" => %{pair_id => entry}}`) into
  # `{concat, altname, pair_id, ws_symbol, instrument_info}` tuples. No
  # HTTP involved — kept separate from `fetch_instruments/0` so it's
  # directly unit-testable against a canned fixture.
  @spec parse_instruments(map()) :: [
          {String.t(), String.t(), String.t(), String.t(), instrument_info()}
        ]
  def parse_instruments(%{"result" => result}) when is_map(result) do
    result
    |> Enum.filter(fn {_pair_id, entry} -> is_map(entry) and entry["status"] == "online" end)
    |> Enum.flat_map(&parse_pair/1)
  end

  def parse_instruments(_other), do: []

  defp parse_pair(
         {pair_id,
          %{
            "altname" => altname,
            "base" => base,
            "quote" => quote_ccy,
            "pair_decimals" => pair_decimals,
            "lot_decimals" => lot_decimals,
            "ordermin" => ordermin
          } = entry}
       )
       when is_binary(pair_id) and is_binary(altname) and is_binary(base) and
              is_binary(quote_ccy) and is_integer(pair_decimals) and is_integer(lot_decimals) and
              is_binary(ordermin) do
    concat = concat_symbol(altname)
    ws_symbol = asset_code_to_ticker(base) <> "/" <> asset_code_to_ticker(quote_ccy)

    info = %{
      tick_size: entry["tick_size"] || pow10_string(pair_decimals),
      step_size: pow10_string(lot_decimals),
      min_qty: ordermin
    }

    [{concat, altname, pair_id, ws_symbol, info}]
  end

  defp parse_pair(_other), do: []

  # Binance-style concat symbol from a Kraken altname: the two legacy
  # tickers that survive in altname (`XBT`, `XDG`) get substituted; every
  # other altname already matches its common ticker unchanged.
  defp concat_symbol(altname) do
    altname
    |> String.replace("XBT", "BTC")
    |> String.replace("XDG", "DOGE")
  end

  defp pow10_string(0), do: "1"

  defp pow10_string(decimals) when is_integer(decimals) and decimals > 0 do
    "0." <> String.duplicate("0", decimals - 1) <> "1"
  end

  defp fetch_instruments do
    config = Application.get_env(:data_collector, :kraken, [])
    base_url = Keyword.get(config, :base_url, "https://api.kraken.com")

    DataCollector.CircuitBreaker.call(:kraken_api, fn ->
      case HTTPoison.get("#{base_url}/0/public/AssetPairs") do
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
