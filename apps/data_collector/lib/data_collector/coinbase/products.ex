defmodule DataCollector.Coinbase.Products do
  @moduledoc """
  Caches the mapping between Binance-style concat symbols (`"BTCUSD"`) and
  Coinbase `product_id`s (`"BTC-USD"`), plus per-product precision/size info
  (`base_increment`/`quote_increment`/`base_min_size`), sourced from the
  **public, unauthenticated**
  `GET /api/v3/brokerage/market/products?product_type=SPOT` mirror endpoint
  (see `docs/superpowers/notes/coinbase-api-verified.md` §3) — using the
  `market/`-prefixed path avoids burning any private JWT/rate-limit budget
  for pure market-data reads.

  Unlike Kraken's `altname`/pair-id/WS-symbol three-way split, Coinbase's
  concat <-> `product_id` mapping is a straight hyphen strip/insert — no
  legacy-ticker substitution table needed, since Coinbase uses plain,
  current tickers throughout (`BTC`, not `XBT`). Each product's own
  `product_id`/`base_currency_id`/`quote_currency_id` fields are cached
  directly (`concat = base_currency_id <> quote_currency_id`).

  Same lazy-load/refresh-once-on-miss pattern as `DataCollector.OKX.Symbols`
  and `DataCollector.Kraken.Symbols`: the product list is loaded on first
  lookup (nothing fetched at application boot), and a cache miss after the
  cache is already warm triggers exactly one refresh attempt (covers a
  product newly listed since the last load) before giving up with
  `{:error, :unknown_symbol}`.

  Only `status == "online"` products are cached — see verified notes §2 for
  why this is treated as the sole tradability signal. No special-casing for
  Coinbase's USDT-quote coverage gap belongs here (verified notes §3): a
  `"XXXUSDT"` concat symbol that Coinbase simply doesn't list returns
  `{:error, :unknown_symbol}` like any other unlisted symbol, which is
  already the correct, honest behavior — that gap is an operational
  pair-selection concern for users, not an adapter ambiguity.
  """

  use GenServer
  require Logger

  alias SharedData.Config

  @table :coinbase_products_cache

  @type product_info :: %{
          base_increment: String.t(),
          quote_increment: String.t(),
          base_min_size: String.t()
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Binance-style concat symbol (`"BTCUSD"`) -> Coinbase `product_id`
  (`"BTC-USD"`).
  """
  @spec to_product_id(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_product_id(concat) when is_binary(concat) do
    lookup({:concat, concat})
  end

  @doc """
  Coinbase `product_id` (`"BTC-USD"`) -> Binance-style concat symbol
  (`"BTCUSD"`).
  """
  @spec to_concat(String.t()) :: {:ok, String.t()} | {:error, :unknown_symbol}
  def to_concat(product_id) when is_binary(product_id) do
    lookup({:product_id, product_id})
  end

  @doc """
  Precision/size info for a symbol, given as a Binance-style concat symbol.
  """
  @spec product_info(String.t()) :: {:ok, product_info()} | {:error, :unknown_symbol}
  def product_info(concat) when is_binary(concat) do
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
        # in case it was newly listed on Coinbase, then give up if still
        # missing.
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
    case fetch_all_products() do
      {:ok, products} ->
        entries = parse_products(%{"products" => products})
        Enum.each(entries, &cache_entry/1)

        Logger.info(
          "DataCollector.Coinbase.Products: cached #{length(entries)} online SPOT products"
        )

        %{state | loaded?: true}

      {:error, reason} ->
        Logger.warning(
          "DataCollector.Coinbase.Products: failed to fetch product list: #{inspect(reason)}"
        )

        state
    end
  end

  @doc false
  # Inserts one parsed products entry (as returned by `parse_products/1`)
  # into the cache table. Public (but `@doc false`) so tests can seed the
  # cache directly from a canned fixture via `parse_products/1` without a
  # live HTTP call — same "factor it out for testability" rationale as
  # `DataCollector.OKX.Symbols.cache_entry/1`.
  @spec cache_entry({String.t(), String.t(), product_info()}) :: true
  def cache_entry({concat, product_id, info}) do
    :ets.insert(@table, {{:concat, concat}, product_id})
    :ets.insert(@table, {{:product_id, product_id}, concat})
    :ets.insert(@table, {{:info, concat}, info})
  end

  @doc false
  # Pure parsing of the (already JSON-decoded) products response body
  # (`%{"products" => [...]}`, per
  # GET /api/v3/brokerage/market/products?product_type=SPOT) into
  # `{concat, product_id, product_info}` tuples. No HTTP involved — kept
  # separate from `fetch_all_products/0` so it's directly unit-testable
  # against a canned fixture. Only `status == "online"` entries are kept.
  @spec parse_products(map()) :: [{String.t(), String.t(), product_info()}]
  def parse_products(%{"products" => products}) when is_list(products) do
    products
    |> Enum.filter(&(&1["status"] == "online"))
    |> Enum.flat_map(&parse_product/1)
  end

  def parse_products(_other), do: []

  defp parse_product(%{
         "product_id" => product_id,
         "base_currency_id" => base_currency_id,
         "quote_currency_id" => quote_currency_id,
         "base_increment" => base_increment,
         "quote_increment" => quote_increment,
         "base_min_size" => base_min_size
       })
       when is_binary(product_id) and base_currency_id not in [nil, ""] and
              quote_currency_id not in [nil, ""] do
    concat = base_currency_id <> quote_currency_id

    info = %{
      base_increment: base_increment,
      quote_increment: quote_increment,
      base_min_size: base_min_size
    }

    [{concat, product_id, info}]
  end

  defp parse_product(_other), do: []

  # Accumulates `products` across every page (`has_next`/`cursor`
  # pagination) into a single flat list before handing off to
  # `parse_products/1`.
  defp fetch_all_products, do: fetch_all_pages(nil, [])

  defp fetch_all_pages(cursor, acc) do
    case fetch_products_page(cursor) do
      {:ok, %{"products" => products} = page} when is_list(products) ->
        acc = acc ++ products

        if page["has_next"] == true and is_binary(page["cursor"]) and page["cursor"] != "" do
          fetch_all_pages(page["cursor"], acc)
        else
          {:ok, acc}
        end

      {:ok, _other} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_products_page(cursor) do
    config = Application.get_env(:data_collector, :coinbase, [])
    base_url = Keyword.get(config, :base_url, "https://api.coinbase.com")
    params = maybe_put_cursor(%{product_type: "SPOT"}, cursor)

    DataCollector.CircuitBreaker.call(:coinbase_api, fn ->
      case HTTPoison.get(
             "#{base_url}/api/v3/brokerage/market/products",
             [],
             params: params
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

  defp maybe_put_cursor(params, nil), do: params
  defp maybe_put_cursor(params, ""), do: params

  defp maybe_put_cursor(params, cursor) when is_binary(cursor),
    do: Map.put(params, :cursor, cursor)
end
