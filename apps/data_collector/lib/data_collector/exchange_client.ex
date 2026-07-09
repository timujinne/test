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

  @typedoc """
  Credentials map passed to every private-endpoint callback instead of
  separate `api_key`/`secret_key` positional args. `passphrase` is `nil`
  for exchanges that don't require one (e.g. Binance); OKX requires it.
  """
  @type credentials :: %{
          api_key: Types.api_key(),
          secret_key: Types.secret_key(),
          passphrase: String.t() | nil
        }

  @callback get_account(credentials()) :: Types.result(map())

  @callback create_order(credentials(), Types.order_params()) :: Types.result(Types.order())

  @callback cancel_order(credentials(), Types.symbol(), Types.order_id()) ::
              Types.result(map())

  @callback get_open_orders(credentials(), Types.symbol() | nil) :: Types.result([map()])

  @callback get_exchange_info(Types.symbol()) :: Types.result(map())
end
