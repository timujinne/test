defmodule DataCollector.MarketData do
  @moduledoc """
  Market data aggregator that periodically fetches and broadcasts market data.
  """

  use GenServer
  require Logger

  @update_interval 5_000 # 5 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    # Schedule first update
    schedule_update()

    state = %{
      symbols: ["BTCUSDT", "ETHUSDT", "BNBUSDT"],
      prices: %{}
    }

    {:ok, state}
  end

  @doc """
  Get current price for a symbol.
  """
  def get_price(symbol) do
    GenServer.call(__MODULE__, {:get_price, symbol})
  end

  @doc """
  Subscribe to price updates via PubSub.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(SharedData.PubSub, "market_data")
  end

  def handle_call({:get_price, symbol}, _from, state) do
    price = Map.get(state.prices, symbol)
    {:reply, price, state}
  end

  def handle_info(:update, state) do
    # Fetch prices for all symbols
    new_prices =
      Enum.reduce(state.symbols, state.prices, fn symbol, acc ->
        case DataCollector.BinanceClient.get_ticker_price(symbol) do
          {:ok, %{price: price}} ->
            Map.put(acc, symbol, price)

          {:error, reason} ->
            Logger.error("Failed to get price for #{symbol}: #{inspect(reason)}")
            acc
        end
      end)

    # Broadcast updates
    Phoenix.PubSub.broadcast(
      SharedData.PubSub,
      "market_data",
      {:price_update, new_prices}
    )

    # Schedule next update
    schedule_update()

    {:noreply, %{state | prices: new_prices}}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @update_interval)
  end
end
