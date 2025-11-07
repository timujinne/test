defmodule DataCollector.BinanceWebSocket do
  @moduledoc """
  WebSocket client for Binance streams.
  Handles user data stream and market data streams.
  """
  use WebSockex
  require Logger

  @base_url "wss://stream.binance.com:9443"

  def start_link(opts) do
    stream = Keyword.fetch!(opts, :stream)
    url = "#{@base_url}/ws/#{stream}"
    
    WebSockex.start_link(url, __MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, state)
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to decode WebSocket message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame({:ping, _}, state) do
    {:reply, :pong, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("WebSocket disconnected: #{inspect(reason)}")
    {:reconnect, state}
  end

  # Private functions

  defp handle_message(%{"e" => "executionReport"} = data, _state) do
    Logger.debug("Execution report: #{inspect(data)}")
    
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "order_updates",
      {:execution_report, data}
    )
  end

  defp handle_message(%{"e" => "outboundAccountPosition"} = data, _state) do
    Logger.debug("Account position update: #{inspect(data)}")
    
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "balance_updates",
      {:balance_update, data}
    )
  end

  defp handle_message(%{"e" => "24hrTicker"} = data, _state) do
    symbol = data["s"]
    
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "market:#{symbol}",
      {:ticker, data}
    )
  end

  defp handle_message(%{"e" => "trade"} = data, _state) do
    symbol = data["s"]
    
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "market:#{symbol}",
      {:trade, data}
    )
  end

  defp handle_message(data, _state) do
    Logger.debug("Unhandled message: #{inspect(data)}")
  end
end
