defmodule DashboardWeb.Components.Trading.OrderForm do
  @moduledoc """
  Order creation form component.
  Supports LIMIT and MARKET orders with BUY/SELL sides.
  """
  use Phoenix.Component

  attr :form, :map, required: true
  attr :symbol, :string, required: true
  attr :current_price, :any, default: nil
  attr :available_balance, :string, default: "0.00"
  attr :base_asset, :string, default: "BTC"
  attr :quote_asset, :string, default: "USDT"

  @doc """
  Renders the order form component.

  ## Examples

      <.order_form
        form={%{"side" => "BUY", "type" => "LIMIT", "price" => "42000", "quantity" => "0.5"}}
        symbol="BTCUSDT"
        current_price={42000.50}
        available_balance="1000.00"
        base_asset="BTC"
        quote_asset="USDT"
      />
  """
  def order_form(assigns) do
    assigns =
      assigns
      |> assign(:side, Map.get(assigns.form, "side", "BUY"))
      |> assign(:type, Map.get(assigns.form, "type", "LIMIT"))
      |> assign(:price, Map.get(assigns.form, "price", ""))
      |> assign(:quantity, Map.get(assigns.form, "quantity", ""))
      |> assign(:total, calculate_total(assigns.form, assigns.current_price))

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body p-4">
        <%!-- BUY/SELL Tabs --%>
        <div class="tabs tabs-boxed mb-4" role="tablist">
          <button
            type="button"
            class={"tab flex-1 " <> if(@side == "BUY", do: "tab-active bg-success text-success-content", else: "")}
            phx-click="change_side"
            phx-value-side="BUY"
            role="tab"
            aria-selected={@side == "BUY"}
          >
            Buy
          </button>
          <button
            type="button"
            class={"tab flex-1 " <> if(@side == "SELL", do: "tab-active bg-error text-error-content", else: "")}
            phx-click="change_side"
            phx-value-side="SELL"
            role="tab"
            aria-selected={@side == "SELL"}
          >
            Sell
          </button>
        </div>

        <%!-- Order Type --%>
        <div class="form-control mb-3">
          <label class="label py-1">
            <span class="label-text text-xs">Order Type</span>
          </label>
          <select
            name="order_type"
            class="select select-sm w-full"
            phx-change="change_order_type"
          >
            <option value="LIMIT" selected={@type == "LIMIT"}>Limit</option>
            <option value="MARKET" selected={@type == "MARKET"}>Market</option>
          </select>
        </div>

        <%!-- Price Input (only for LIMIT orders) --%>
        <%= if @type == "LIMIT" do %>
          <div class="form-control mb-3">
            <label class="label py-1">
              <span class="label-text text-xs">Price</span>
              <%= if @current_price do %>
                <span class="label-text-alt text-xs">
                  ≈ {format_price(@current_price)}
                </span>
              <% end %>
            </label>
            <label class="input input-sm flex items-center gap-2">
              <input
                type="text"
                name="price"
                value={@price}
                placeholder="0.00"
                class="grow font-mono"
                phx-change="update_price"
              />
              <span class="text-xs text-base-content/60">{@quote_asset}</span>
            </label>
          </div>
        <% end %>

        <%!-- Amount Input with % buttons --%>
        <div class="form-control mb-3">
          <label class="label py-1">
            <span class="label-text text-xs">Amount</span>
            <span class="label-text-alt text-xs">
              Available: {@available_balance} {if @side == "BUY", do: @quote_asset, else: @base_asset}
            </span>
          </label>
          <label class="input input-sm flex items-center gap-2">
            <input
              type="text"
              name="quantity"
              value={@quantity}
              placeholder="0.00"
              class="grow font-mono"
              phx-change="update_quantity"
            />
            <span class="text-xs text-base-content/60">{@base_asset}</span>
          </label>
        </div>

        <%!-- Percentage Buttons --%>
        <div class="flex gap-2 mb-4">
          <button
            type="button"
            class="btn btn-xs btn-outline flex-1"
            phx-click="set_percentage"
            phx-value-percent="25"
          >
            25%
          </button>
          <button
            type="button"
            class="btn btn-xs btn-outline flex-1"
            phx-click="set_percentage"
            phx-value-percent="50"
          >
            50%
          </button>
          <button
            type="button"
            class="btn btn-xs btn-outline flex-1"
            phx-click="set_percentage"
            phx-value-percent="75"
          >
            75%
          </button>
          <button
            type="button"
            class="btn btn-xs btn-outline flex-1"
            phx-click="set_percentage"
            phx-value-percent="100"
          >
            100%
          </button>
        </div>

        <%!-- Total Preview --%>
        <div class="bg-base-200 rounded-lg p-3 mb-4">
          <div class="flex justify-between items-center">
            <span class="text-xs text-base-content/60">Total</span>
            <span class="font-mono text-sm font-semibold">
              {@total} {@quote_asset}
            </span>
          </div>
        </div>

        <%!-- Submit Button --%>
        <button
          type="submit"
          class={"btn btn-block " <> if(@side == "BUY", do: "btn-success", else: "btn-error")}
          phx-click="place_order"
          disabled={!is_valid_order?(@form, @type)}
        >
          {@side} {@base_asset}
        </button>

        <%!-- Order Summary --%>
        <div class="mt-3 text-xs text-base-content/60 space-y-1">
          <div class="flex justify-between">
            <span>Order Type:</span>
            <span class="font-mono">{@type}</span>
          </div>
          <%= if @type == "LIMIT" and @price != "" do %>
            <div class="flex justify-between">
              <span>Price:</span>
              <span class="font-mono">{@price} {@quote_asset}</span>
            </div>
          <% end %>
          <%= if @quantity != "" do %>
            <div class="flex justify-between">
              <span>Amount:</span>
              <span class="font-mono">{@quantity} {@base_asset}</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Calculates the total value of the order.
  # For LIMIT orders: price * quantity
  # For MARKET orders: current_price * quantity
  defp calculate_total(form, current_price) do
    type = Map.get(form, "type", "LIMIT")
    quantity_str = Map.get(form, "quantity", "")
    price_str = Map.get(form, "price", "")

    with {quantity, ""} <- Float.parse(quantity_str),
         price <- get_effective_price(type, price_str, current_price),
         true <- is_number(price) and price > 0 do
      total = quantity * price
      :erlang.float_to_binary(total, decimals: 2)
    else
      _ -> "0.00"
    end
  end

  # Gets the effective price for the order based on type.
  defp get_effective_price("LIMIT", price_str, _current_price) do
    case Float.parse(price_str) do
      {price, ""} -> price
      _ -> 0
    end
  end

  defp get_effective_price("MARKET", _price_str, current_price) when is_number(current_price) do
    current_price
  end

  defp get_effective_price("MARKET", _price_str, _current_price), do: 0

  # Formats price for display.
  defp format_price(price) when is_float(price) do
    :erlang.float_to_binary(price, decimals: 2)
  end

  defp format_price(price) when is_integer(price) do
    format_price(price * 1.0)
  end

  defp format_price(price) when is_binary(price), do: price
  defp format_price(_), do: "0.00"

  # Validates if the order form has sufficient information to place an order.
  defp is_valid_order?(form, "LIMIT") do
    quantity_str = Map.get(form, "quantity", "")
    price_str = Map.get(form, "price", "")

    case {Float.parse(quantity_str), Float.parse(price_str)} do
      {{quantity, ""}, {price, ""}} when quantity > 0 and price > 0 -> true
      _ -> false
    end
  end

  defp is_valid_order?(form, "MARKET") do
    quantity_str = Map.get(form, "quantity", "")

    case Float.parse(quantity_str) do
      {quantity, ""} when quantity > 0 -> true
      _ -> false
    end
  end
end
