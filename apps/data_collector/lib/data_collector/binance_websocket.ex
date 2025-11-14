defmodule DataCollector.BinanceWebSocket do
  @moduledoc """
  WebSocket client for Binance streams with exponential backoff.

  Handles user data stream and market data streams with automatic
  reconnection using exponential backoff strategy.

  ## Reconnection Strategy

  - Initial backoff: 1 second
  - Max backoff: 5 minutes
  - Backoff multiplier: 2x
  - Max reconnect attempts: 10
  - Includes jitter to prevent thundering herd
  """
  use WebSockex
  require Logger

  alias SharedData.Config

  @base_url "wss://stream.binance.com:9443"

  def start_link(opts) do
    stream = Keyword.fetch!(opts, :stream)
    url = "#{@base_url}/ws/#{stream}"

    initial_state = %{
      stream: stream,
      reconnect_attempts: 0,
      decode_errors: 0
    }

    WebSockex.start_link(url, __MODULE__, Map.merge(initial_state, Enum.into(opts, %{})), name: __MODULE__)
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, state)
        # Reset decode errors counter on successful decode
        {:ok, %{state | decode_errors: 0}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        Failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        # Increment decode errors counter
        new_state = %{state | decode_errors: state.decode_errors + 1}

        # If too many decode errors, reconnect
        if new_state.decode_errors > 10 do
          Logger.error("Too many decode errors (#{new_state.decode_errors}), reconnecting...")
          {:close, :too_many_errors, new_state}
        else
          {:ok, new_state}
        end
    end
  end

  @impl true
  def handle_frame({:ping, _}, state) do
    {:reply, :pong, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    attempts = state.reconnect_attempts + 1
    max_attempts = Config.websocket(:max_reconnect_attempts)

    if attempts >= max_attempts do
      Logger.error("""
      WebSocket max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      # Calculate backoff time with jitter
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      WebSocket disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      # Sleep for backoff time
      Process.sleep(backoff_ms)

      # Update state and reconnect
      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0}
      {:reconnect, new_state}
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("""
    WebSocket connected successfully
    Stream: #{state.stream}
    Resetting reconnect attempts counter
    """)

    # Reset counters on successful connection
    new_state = %{state | reconnect_attempts: 0, decode_errors: 0}
    {:ok, new_state}
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

  # Calculate exponential backoff with jitter
  defp calculate_backoff(attempts) do
    base_backoff = Config.websocket(:initial_backoff)
    max_backoff = Config.websocket(:max_backoff)
    multiplier = Config.websocket(:backoff_multiplier)

    # Exponential backoff: base * multiplier^(attempts-1)
    backoff = base_backoff * :math.pow(multiplier, attempts - 1)
    capped_backoff = min(trunc(backoff), max_backoff)

    # Add random jitter (±20%) to prevent thundering herd
    jitter_range = trunc(capped_backoff * 0.2)
    jitter = :rand.uniform(jitter_range * 2 + 1) - jitter_range - 1

    max(capped_backoff + jitter, base_backoff)
  end
end
