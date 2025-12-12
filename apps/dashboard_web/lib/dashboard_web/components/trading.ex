defmodule DashboardWeb.Components.Trading do
  @moduledoc """
  Trading-related UI components.

  This module provides a collection of Phoenix LiveView components
  for building trading interfaces, including order books, order forms,
  conditional chains, and other trading-specific UI elements.

  ## Available Components

  - `order_book/1` - Displays real-time bid/ask order book (стакан заявок)
  - `order_form/1` - Form for creating BUY/SELL orders (LIMIT/MARKET)
  - `chain_step/1` - Single step in a conditional chain
  - `branch_editor/1` - Conditional branch editor with two paths
  - `chain_builder/1` - Visual chain constructor
  - `chain_monitor/1` - Real-time chain execution monitor

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

      <.chain_builder
        chain={@chain_form}
        symbols={@available_symbols}
        on_save="save_chain"
        on_cancel="cancel_builder"
      />

      <.chain_monitor
        chain={@active_chain}
        current_price={@current_price}
        on_stop="stop_chain"
        on_cancel="cancel_chain"
      />
  """

  defdelegate order_book(assigns), to: DashboardWeb.Components.Trading.OrderBook
  defdelegate order_form(assigns), to: DashboardWeb.Components.Trading.OrderForm
  defdelegate chain_step(assigns), to: DashboardWeb.Components.Trading.ChainStep
  defdelegate branch_editor(assigns), to: DashboardWeb.Components.Trading.BranchEditor
  defdelegate chain_builder(assigns), to: DashboardWeb.Components.Trading.ChainBuilder
  defdelegate chain_monitor(assigns), to: DashboardWeb.Components.Trading.ChainMonitor
end
