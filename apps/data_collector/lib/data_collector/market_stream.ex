defmodule DataCollector.MarketStream do
  @moduledoc """
  Exchange-agnostic facade over the per-exchange public market-data
  streams, so `TradingEngine.Trader` can subscribe to ticker updates
  without knowing which stream module backs a given exchange.

  Deliberately pattern-matches known exchange strings rather than
  converting the input to an atom (same security invariant as
  `DataCollector.ExchangeRegistry`).
  """

  @doc """
  Subscribes to ticker updates for `concat_symbol` (Binance-style, e.g.
  `"BTCUSDT"`) on `exchange`. Returns `{:ok, subscriber_count}` on success,
  mirroring `DataCollector.TickerStream.subscribe/1`'s contract.
  """
  @spec subscribe(String.t(), String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def subscribe("binance", concat_symbol), do: DataCollector.TickerStream.subscribe(concat_symbol)
  def subscribe("okx", concat_symbol), do: DataCollector.OKXPublicStream.subscribe(concat_symbol)
  def subscribe(other, _concat_symbol), do: {:error, {:unsupported_exchange, other}}

  @doc """
  Unsubscribes from ticker updates for `concat_symbol` on `exchange`.
  Returns `{:ok, remaining_count}`.
  """
  @spec unsubscribe(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def unsubscribe("binance", concat_symbol),
    do: DataCollector.TickerStream.unsubscribe(concat_symbol)

  def unsubscribe("okx", concat_symbol),
    do: DataCollector.OKXPublicStream.unsubscribe(concat_symbol)

  def unsubscribe(other, _concat_symbol), do: {:error, {:unsupported_exchange, other}}
end
