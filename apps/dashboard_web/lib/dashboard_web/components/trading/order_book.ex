defmodule DashboardWeb.Components.Trading.OrderBook do
  @moduledoc """
  Order Book (стакан заявок) component.
  Displays real-time bid/ask orders with fixed height layout.
  """
  use Phoenix.Component

  attr :bids, :list, default: []
  attr :asks, :list, default: []
  attr :symbol, :string, required: true
  attr :precision, :integer, default: 2
  attr :rows, :integer, default: 8

  @doc """
  Renders the order book component with bids and asks.
  Fixed height, no jumping layout.
  """
  def order_book(assigns) do
    rows_per_side = assigns.rows

    # Sort asks ascending (lowest first, closest to spread)
    asks_sorted =
      assigns.asks
      |> Enum.sort_by(fn {price, _} -> price end, :asc)
      |> Enum.take(rows_per_side)
      |> pad_rows(rows_per_side)

    # Sort bids descending (highest first, closest to spread)
    bids_sorted =
      assigns.bids
      |> Enum.sort_by(fn {price, _} -> price end, :desc)
      |> Enum.take(rows_per_side)
      |> pad_rows(rows_per_side)

    max_volume = calculate_max_volume(assigns.asks, assigns.bids)
    spread = calculate_spread(assigns.bids, assigns.asks)

    assigns =
      assigns
      |> assign(:asks_display, Enum.reverse(asks_sorted))  # Reverse so highest ask at top
      |> assign(:bids_display, bids_sorted)
      |> assign(:max_volume, max_volume)
      |> assign(:spread, spread)
      |> assign(:rows_per_side, rows_per_side)

    ~H"""
    <div class="card bg-base-100 shadow-xl h-full">
      <div class="card-body p-3">
        <h2 class="card-title text-sm mb-1">Order Book</h2>

        <%!-- Header --%>
        <div class="grid grid-cols-3 gap-1 text-xs font-semibold text-base-content/60 border-b border-base-300 pb-1">
          <div class="text-left">Price</div>
          <div class="text-right">Amount</div>
          <div class="text-right">Total</div>
        </div>

        <%!-- Fixed height container --%>
        <div class="flex flex-col" style="height: 400px;">
          <%!-- Asks (sellers - red) - fixed height --%>
          <div class="flex-1 flex flex-col justify-end overflow-hidden">
            <%= for row <- @asks_display do %>
              <.order_row row={row} side={:ask} max_volume={@max_volume} precision={@precision} />
            <% end %>
          </div>

          <%!-- Spread - fixed height --%>
          <div class="h-10 flex items-center justify-center bg-base-200 rounded my-1 shrink-0">
            <%= if @spread do %>
              <% {spread_value, spread_percent} = @spread %>
              <div class="text-center">
                <span class="font-mono text-sm font-bold text-base-content">
                  <%= format_price(spread_value, @precision) %>
                </span>
                <span class="text-xs text-base-content/60 ml-2">
                  (<%= :erlang.float_to_binary(spread_percent, decimals: 3) %>%)
                </span>
              </div>
            <% else %>
              <span class="text-xs text-base-content/50">Loading...</span>
            <% end %>
          </div>

          <%!-- Bids (buyers - green) - fixed height --%>
          <div class="flex-1 flex flex-col overflow-hidden">
            <%= for row <- @bids_display do %>
              <.order_row row={row} side={:bid} max_volume={@max_volume} precision={@precision} />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Single row component
  attr :row, :any, required: true
  attr :side, :atom, required: true
  attr :max_volume, :float, required: true
  attr :precision, :integer, required: true

  defp order_row(%{row: nil} = assigns) do
    ~H"""
    <div class="h-5 flex items-center">
      <div class="grid grid-cols-3 gap-1 text-xs w-full opacity-30">
        <div class="text-left font-mono">-</div>
        <div class="text-right font-mono">-</div>
        <div class="text-right font-mono">-</div>
      </div>
    </div>
    """
  end

  defp order_row(%{row: {price, qty}} = assigns) do
    total = price * qty
    volume_percent = if assigns.max_volume > 0, do: (qty / assigns.max_volume) * 100, else: 0
    color_class = if assigns.side == :ask, do: "text-error", else: "text-success"
    bg_class = if assigns.side == :ask, do: "bg-error/10", else: "bg-success/10"

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:volume_percent, volume_percent)
      |> assign(:color_class, color_class)
      |> assign(:bg_class, bg_class)

    ~H"""
    <div class="h-5 flex items-center relative">
      <%!-- Volume bar background --%>
      <div
        class={["absolute right-0 top-0 bottom-0 rounded-sm", @bg_class]}
        style={"width: #{min(@volume_percent, 100)}%"}
      />
      <%!-- Data --%>
      <div class="relative grid grid-cols-3 gap-1 text-xs w-full">
        <div class={["text-left font-mono font-medium", @color_class]}>
          <%= format_price(elem(@row, 0), @precision) %>
        </div>
        <div class="text-right font-mono text-base-content/80">
          <%= format_qty(elem(@row, 1)) %>
        </div>
        <div class="text-right font-mono text-base-content/60">
          <%= format_total(@total) %>
        </div>
      </div>
    </div>
    """
  end

  # Pad list to fixed length with nil values
  defp pad_rows(list, target_length) when length(list) >= target_length do
    Enum.take(list, target_length)
  end

  defp pad_rows(list, target_length) do
    padding = List.duplicate(nil, target_length - length(list))
    list ++ padding
  end

  # Formats price with specified precision.
  defp format_price(price, precision) when is_float(price) do
    :erlang.float_to_binary(price, decimals: precision)
  end

  defp format_price(price, precision) when is_integer(price) do
    format_price(price * 1.0, precision)
  end

  defp format_price(price, _precision) when is_binary(price), do: price

  # Formats quantity - compact format
  defp format_qty(qty) when is_float(qty) do
    cond do
      qty >= 1 -> :erlang.float_to_binary(qty, decimals: 4)
      qty >= 0.01 -> :erlang.float_to_binary(qty, decimals: 5)
      true -> :erlang.float_to_binary(qty, decimals: 6)
    end
  end

  defp format_qty(qty) when is_integer(qty), do: format_qty(qty * 1.0)
  defp format_qty(qty) when is_binary(qty), do: qty

  # Formats total value.
  defp format_total(total) when is_float(total) do
    cond do
      total >= 1000 -> "#{:erlang.float_to_binary(total / 1000, decimals: 1)}K"
      total >= 1 -> :erlang.float_to_binary(total, decimals: 2)
      true -> :erlang.float_to_binary(total, decimals: 4)
    end
  end

  defp format_total(total) when is_integer(total), do: format_total(total * 1.0)
  defp format_total(total) when is_binary(total), do: total

  # Calculates spread between best bid and best ask.
  defp calculate_spread([], _), do: nil
  defp calculate_spread(_, []), do: nil

  defp calculate_spread(bids, asks) do
    best_bid = bids |> Enum.map(fn {price, _} -> price end) |> Enum.max(fn -> 0 end)
    best_ask = asks |> Enum.map(fn {price, _} -> price end) |> Enum.min(fn -> 0 end)

    if best_bid > 0 and best_ask > 0 and best_ask > best_bid do
      spread = best_ask - best_bid
      percent = spread / best_ask * 100
      {spread, percent}
    else
      nil
    end
  end

  # Calculates maximum volume for scaling the volume bars.
  defp calculate_max_volume(asks, bids) do
    all_quantities =
      (asks ++ bids)
      |> Enum.map(fn {_price, qty} -> qty end)

    case all_quantities do
      [] -> 1.0
      quantities -> Enum.max(quantities)
    end
  end
end
