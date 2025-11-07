defmodule TradingEngine.OrderManager do
  @moduledoc """
  Manages order lifecycle and synchronization with Binance.
  """
  require Logger

  alias DataCollector.BinanceClient
  alias SharedData.Repo
  alias SharedData.Schemas.Order

  def create_order(account_id, api_key, secret_key, order_params) do
    # Create order on Binance
    case BinanceClient.create_order(api_key, secret_key, order_params) do
      {:ok, binance_order} ->
        # Save to database
        order_attrs = %{
          order_id: to_string(binance_order["orderId"]),
          client_order_id: binance_order["clientOrderId"],
          symbol: binance_order["symbol"],
          type: binance_order["type"],
          side: binance_order["side"],
          price: binance_order["price"],
          quantity: binance_order["origQty"],
          filled_qty: binance_order["executedQty"],
          status: binance_order["status"],
          time_in_force: binance_order["timeInForce"],
          account_id: account_id
        }

        %Order{}
        |> Order.changeset(order_attrs)
        |> Repo.insert()

      error ->
        error
    end
  end

  def cancel_order(account_id, api_key, secret_key, symbol, order_id) do
    case BinanceClient.cancel_order(api_key, secret_key, symbol, order_id) do
      {:ok, canceled_order} ->
        # Update order in database
        order = Repo.get_by(Order, order_id: order_id, account_id: account_id)

        if order do
          order
          |> Order.changeset(%{status: "CANCELED"})
          |> Repo.update()
        end

        {:ok, canceled_order}

      error ->
        error
    end
  end

  def update_order_from_execution(execution) do
    order_id = to_string(execution["i"])

    order = Repo.get_by(Order, order_id: order_id)

    if order do
      updates = %{
        filled_qty: execution["z"],
        status: execution["X"]
      }

      order
      |> Order.changeset(updates)
      |> Repo.update()
    end
  end
end
