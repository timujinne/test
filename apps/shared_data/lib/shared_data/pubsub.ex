defmodule SharedData.PubSub do
  @moduledoc ~S"""
  Centralized PubSub module for the Binance Trading System.

  All applications in the umbrella project use a single Phoenix.PubSub instance
  named `BinanceSystem.PubSub`, which is started in DataCollector.Application.

  ## Topics

  ### Market Data
  - `market:#{symbol}` - Ticker and trade updates for a specific symbol
    - Messages: `{:ticker, data}`, `{:trade, data}`
    - Publishers: BinanceWebSocket
    - Subscribers: MarketData, Trader, TradingLive

  ### Trading Updates
  - `order_updates` - Order execution reports
    - Messages: `{:execution_report, data}`
    - Publishers: BinanceWebSocket
    - Subscribers: Trader, TradingLive

  - `balance_updates` - Account balance updates
    - Messages: `{:balance_update, data}`
    - Publishers: BinanceWebSocket
    - Subscribers: PortfolioLive

  ## Usage

      # Subscribe to a topic
      SharedData.PubSub.subscribe("market:BTCUSDT")

      # Broadcast a message
      SharedData.PubSub.broadcast("market:BTCUSDT", {:ticker, data})

      # Get PubSub name for direct Phoenix.PubSub calls
      pubsub = SharedData.PubSub.name()
  """

  @pubsub_name BinanceSystem.PubSub

  @doc """
  Returns the PubSub instance name.
  """
  def name, do: @pubsub_name

  @doc """
  Subscribes the current process to the given topic.

  ## Examples

      iex> SharedData.PubSub.subscribe("market:BTCUSDT")
      :ok
  """
  def subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic)
  end

  @doc """
  Broadcasts a message to all subscribers of the given topic.

  ## Examples

      iex> SharedData.PubSub.broadcast("market:BTCUSDT", {:ticker, %{}})
      :ok
  """
  def broadcast(topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast(@pubsub_name, topic, message)
  end

  @doc """
  Broadcasts a message to all subscribers except the sender.

  ## Examples

      iex> SharedData.PubSub.broadcast_from(self(), "market:BTCUSDT", {:ticker, %{}})
      :ok
  """
  def broadcast_from(from, topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast_from(@pubsub_name, from, topic, message)
  end

  @doc """
  Unsubscribes the current process from the given topic.

  ## Examples

      iex> SharedData.PubSub.unsubscribe("market:BTCUSDT")
      :ok
  """
  def unsubscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, topic)
  end
end
