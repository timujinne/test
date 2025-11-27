defmodule DashboardWeb.Components.Trading.PriceChart do
  @moduledoc """
  PriceChart component - displays candlestick chart with volume using Lightweight Charts.

  ## Usage

      <PriceChart.price_chart id="btcusdt-chart" />

  ## LiveView Integration

  The hook expects these events from the LiveView:

    - `price_chart_init` - Initial data load with historical candles
    - `price_chart_update` - Real-time updates for the latest candle

  Example in LiveView:

      def mount(_params, _session, socket) do
        # Load initial candles
        candles = fetch_candles("BTCUSDT", "1m", 100)

        # Push initial data to hook
        push_event(socket, "price_chart_init", %{candles: candles})

        {:ok, socket}
      end

      def handle_info({:ticker, ticker_data}, socket) do
        # Update chart with new candle data
        candle = %{
          time: System.system_time(:millisecond),
          open: ticker_data.open,
          high: ticker_data.high,
          low: ticker_data.low,
          close: ticker_data.close,
          volume: ticker_data.volume
        }

        push_event(socket, "price_chart_update", candle)

        {:noreply, socket}
      end
  """
  use Phoenix.Component

  @doc """
  Renders a price chart with candlestick and volume series.

  ## Attributes

    - `id` - Required. Unique identifier for the chart element
    - `class` - Optional. Additional CSS classes to apply to the card wrapper
  """
  attr :id, :string, required: true
  attr :class, :string, default: ""

  def price_chart(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-xl", @class]}>
      <div class="card-body p-4">
        <div id={@id} phx-hook="PriceChart" phx-update="ignore" class="w-full h-96"></div>
      </div>
    </div>
    """
  end
end
