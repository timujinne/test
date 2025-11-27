defmodule DashboardWeb.Components.Trading do
  @moduledoc """
  Trading-related UI components.

  This module provides a collection of Phoenix LiveView components
  for building trading interfaces, including order books, order forms,
  and other trading-specific UI elements.

  ## Available Components

  - `order_book/1` - Displays real-time bid/ask order book (стакан заявок)
  - `order_form/1` - Form for creating BUY/SELL orders (LIMIT/MARKET)

  ## Usage

  Import this module in your LiveView:

      import DashboardWeb.Components.Trading

  Then use the components in your template:

      <.order_book
        symbol="BTCUSDT"
        bids={@bids}
        asks={@asks}
      />

      <.order_form
        form={@order_form}
        symbol={@symbol}
        current_price={@current_price}
        available_balance={@balance}
      />
  """

  defdelegate order_book(assigns), to: DashboardWeb.Components.Trading.OrderBook
  defdelegate order_form(assigns), to: DashboardWeb.Components.Trading.OrderForm
end
