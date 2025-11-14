defmodule SharedData.Types do
  @moduledoc """
  Common type definitions for the Binance Trading System.

  This module defines types used across different applications in the umbrella project
  to ensure type safety and improve Dialyzer analysis.

  ## Usage

      # In a module
      @type my_custom_type :: SharedData.Types.account_id()

      # In a @spec
      @spec get_account(SharedData.Types.api_key(), SharedData.Types.secret_key()) ::
        {:ok, map()} | {:error, term()}
  """

  # Account identifiers
  @type account_id :: pos_integer()
  @type user_id :: pos_integer()

  # API credentials
  @type api_key :: String.t()
  @type secret_key :: String.t()

  # Trading symbols and identifiers
  @type symbol :: String.t()
  @type order_id :: pos_integer()
  @type trade_id :: pos_integer()

  # Numeric types
  @type price :: Decimal.t()
  @type quantity :: Decimal.t()
  @type amount :: Decimal.t()
  @type percentage :: Decimal.t()

  # Time
  @type timestamp :: pos_integer()
  @type datetime :: DateTime.t()

  # Order parameters
  @type order_side :: String.t()  # "BUY" | "SELL"
  @type order_type :: String.t()  # "MARKET" | "LIMIT" | "STOP_LOSS" etc.
  @type order_status :: String.t()  # "NEW" | "FILLED" | "CANCELED" etc.
  @type time_in_force :: String.t()  # "GTC" | "IOC" | "FOK"

  @type order_params :: %{
          required(:symbol) => symbol(),
          required(:side) => order_side(),
          required(:type) => order_type(),
          optional(:quantity) => quantity(),
          optional(:price) => price(),
          optional(:quoteOrderQty) => amount(),
          optional(:timeInForce) => time_in_force(),
          optional(:timestamp) => timestamp(),
          optional(:recvWindow) => non_neg_integer()
        }

  # Order response from Binance
  @type order :: %{
          String.t() => any()
        }

  # Market data
  @type market_data :: %{
          String.t() => any()
        }

  @type ticker :: %{
          String.t() => any()
        }

  @type trade :: %{
          String.t() => any()
        }

  # WebSocket messages
  @type execution_report :: %{
          String.t() => any()
        }

  @type balance_update :: %{
          String.t() => any()
        }

  # Strategy types
  @type strategy_name :: atom()
  @type strategy_config :: map()
  @type strategy_state :: map()
  @type strategy_action :: :noop | {:place_order, order_params()}

  # GenServer types
  @type genserver_name :: atom() | {:via, module(), term()}
  @type genserver_ref :: pid() | genserver_name()

  # Common return types
  @type ok_result(value) :: {:ok, value}
  @type error_result :: {:error, term()}
  @type result(value) :: ok_result(value) | error_result()
end
