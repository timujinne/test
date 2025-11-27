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

  - `depth:#{symbol}` - Order book depth updates for a specific symbol
    - Messages: `{:depth_update, data}`
    - Publishers: DepthStream
    - Subscribers: TradingLive

  - `kline:#{symbol}:#{interval}` - Candlestick data for a specific symbol and interval
    - Messages: `{:kline_update, candle}`
    - Publishers: KlineStream
    - Subscribers: TradingLive

  ### Trading Updates
  - `order_updates` - Order execution reports from WebSocket
    - Messages: `{:execution_report, data}`
    - Publishers: BinanceWebSocket
    - Subscribers: Trader, TradingLive

  - `orders:all` - All order lifecycle events (created, filled, cancelled)
    - Messages: `{:order_created, order}`, `{:order_filled, execution}`,
                `{:order_cancelled, execution}`, `{:order_partially_filled, execution}`
    - Publishers: Trader
    - Subscribers: TradingLive, HistoryLive

  - `orders:#{account_id}` - Order lifecycle events for a specific account
    - Messages: `{:order_created, order}`, `{:order_filled, execution}`,
                `{:order_cancelled, execution}`, `{:order_partially_filled, execution}`
    - Publishers: Trader
    - Subscribers: TradingLive (filtered by account)

  - `balance_updates` - Account balance updates
    - Messages: `{:balance_update, data}`
    - Publishers: BinanceWebSocket
    - Subscribers: PortfolioLive

  ### Strategy Management
  - `strategy_updates` - Strategy activation/deactivation commands
    - Messages: `{:strategy_activated, setting}`, `{:strategy_deactivated, setting}`,
                `{:strategy_auto_stopped, setting, reason}`
    - Publishers: SettingsLive, StrategiesLive
    - Subscribers: StrategyManager

  - `strategies:all` - Strategy lifecycle state changes
    - Messages: `{:strategy_started, setting_id, state}`, `{:strategy_stopped, setting_id}`,
                `{:strategy_error, setting_id, reason}`
    - Publishers: StrategyManager
    - Subscribers: StrategiesLive, DashboardLive

  ## Usage

      # Subscribe to a topic
      SharedData.PubSub.subscribe("market:BTCUSDT")

      # Broadcast a message
      SharedData.PubSub.broadcast("market:BTCUSDT", {:ticker, data})

      # Subscribe to order events for all accounts
      SharedData.PubSub.subscribe("orders:all")

      # Subscribe to strategy lifecycle events
      SharedData.PubSub.subscribe("strategies:all")

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
