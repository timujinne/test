defmodule DataCollector.ExchangeClient do
  @moduledoc """
  Behaviour implemented by every exchange REST adapter (Binance, and future
  adapters like Kraken). Callers resolve the adapter module via
  `DataCollector.ExchangeRegistry.client_for/1` instead of calling an adapter
  module by name directly.

  Callback signatures mirror `DataCollector.BinanceClient`'s existing public
  API exactly, so it can implement this behaviour with no changes to its
  function bodies.
  """

  alias SharedData.Types

  @callback get_account(Types.api_key(), Types.secret_key()) :: Types.result(map())

  @callback create_order(Types.api_key(), Types.secret_key(), Types.order_params()) ::
              Types.result(Types.order())

  @callback cancel_order(Types.api_key(), Types.secret_key(), Types.symbol(), Types.order_id()) ::
              Types.result(map())

  @callback get_open_orders(Types.api_key(), Types.secret_key(), Types.symbol() | nil) ::
              Types.result([map()])

  @callback get_exchange_info(Types.symbol()) :: Types.result(map())
end
