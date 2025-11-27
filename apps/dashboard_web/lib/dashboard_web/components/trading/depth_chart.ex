defmodule DashboardWeb.Components.Trading.DepthChart do
  @moduledoc """
  DepthChart component - displays market depth (order book visualization) using Lightweight Charts.

  Shows cumulative bid (buy) and ask (sell) orders as area charts.

  ## Usage

      <DepthChart.depth_chart id="btcusdt-depth" />

  ## LiveView Integration

  The hook expects the `depth_chart_update` event from the LiveView with bids and asks data.

  Example in LiveView:

      def mount(_params, _session, socket) do
        # Subscribe to order book updates
        SharedData.PubSub.subscribe("market:BTCUSDT")

        {:ok, socket}
      end

      def handle_info({:depth_update, depth_data}, socket) do
        # depth_data contains bids and asks as lists of [price, quantity] tuples

        # Send to chart hook
        push_event(socket, "depth_chart_update", %{
          bids: depth_data.bids,  # [[price, qty], ...] sorted descending
          asks: depth_data.asks   # [[price, qty], ...] sorted ascending
        })

        {:noreply, socket}
      end

  ## Data Format

  The hook expects:

    - `bids`: List of [price, quantity] tuples sorted by price descending (highest first)
    - `asks`: List of [price, quantity] tuples sorted by price ascending (lowest first)

  The hook will automatically compute cumulative depth for visualization.
  """
  use Phoenix.Component

  @doc """
  Renders a market depth chart.

  ## Attributes

    - `id` - Required. Unique identifier for the chart element
    - `class` - Optional. Additional CSS classes to apply to the card wrapper
  """
  attr :id, :string, required: true
  attr :class, :string, default: ""

  def depth_chart(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-xl", @class]}>
      <div class="card-body p-2">
        <h3 class="text-sm font-semibold text-base-content/70">Market Depth</h3>
        <div id={@id} phx-hook="DepthChart" phx-update="ignore" class="w-full h-48"></div>
      </div>
    </div>
    """
  end
end
