defmodule DataCollector.WebSocket.Client do
  @moduledoc """
  WebSocket client for Binance real-time market data.

  Connects to Binance WebSocket streams for:
  - Ticker prices
  - Order book updates
  - Trade streams
  - Account updates (user data stream)
  """

  use WebSockex
  require Logger

  @base_url "wss://stream.binance.com:9443/ws"

  def start_link(opts \\ []) do
    streams = Keyword.get(opts, :streams, ["btcusdt@ticker", "ethusdt@ticker", "bnbusdt@ticker"])
    url = build_url(streams)

    WebSockex.start_link(url, __MODULE__, %{streams: streams}, name: __MODULE__)
  end

  @doc """
  Subscribe to additional streams.
  """
  def subscribe(streams) when is_list(streams) do
    WebSockex.cast(__MODULE__, {:subscribe, streams})
  end

  @doc """
  Unsubscribe from streams.
  """
  def unsubscribe(streams) when is_list(streams) do
    WebSockex.cast(__MODULE__, {:unsubscribe, streams})
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected to Binance WebSocket: #{inspect(state.streams)}")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, state)

      {:error, reason} ->
        Logger.error("Failed to decode WebSocket message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame({:binary, _msg}, state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:subscribe, streams}, state) do
    message = %{
      method: "SUBSCRIBE",
      params: streams,
      id: System.unique_integer([:positive])
    }

    {:reply, {:text, Jason.encode!(message)}, state}
  end

  @impl true
  def handle_cast({:unsubscribe, streams}, state) do
    message = %{
      method: "UNSUBSCRIBE",
      params: streams,
      id: System.unique_integer([:positive])
    }

    {:reply, {:text, Jason.encode!(message)}, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("Disconnected from Binance WebSocket: #{inspect(reason)}")
    {:reconnect, state}
  end

  # Private functions

  defp build_url(streams) do
    stream_path = Enum.join(streams, "/")
    "#{@base_url}/#{stream_path}"
  end

  defp handle_message(%{"e" => "24hrTicker"} = data, state) do
    # 24hr ticker price change statistics
    price_data = %{
      symbol: data["s"],
      price: data["c"],
      change_percent: data["P"],
      volume: data["v"],
      high: data["h"],
      low: data["l"]
    }

    # Broadcast to subscribers via PubSub
    Phoenix.PubSub.broadcast(
      SharedData.PubSub,
      "market_data",
      {:ticker_update, price_data}
    )

    {:ok, state}
  end

  defp handle_message(%{"e" => "aggTrade"} = data, state) do
    # Aggregate trade streams
    trade_data = %{
      symbol: data["s"],
      price: data["p"],
      quantity: data["q"],
      time: data["T"],
      is_buyer_maker: data["m"]
    }

    Phoenix.PubSub.broadcast(
      SharedData.PubSub,
      "market_data",
      {:trade_update, trade_data}
    )

    {:ok, state}
  end

  defp handle_message(%{"e" => "depthUpdate"} = data, state) do
    # Order book depth update
    depth_data = %{
      symbol: data["s"],
      bids: data["b"],
      asks: data["a"]
    }

    Phoenix.PubSub.broadcast(
      SharedData.PubSub,
      "market_data",
      {:depth_update, depth_data}
    )

    {:ok, state}
  end

  defp handle_message(data, state) do
    # Log unhandled messages for debugging
    Logger.debug("Unhandled WebSocket message: #{inspect(data)}")
    {:ok, state}
  end
end
