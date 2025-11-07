defmodule DataCollector.WebSocket.Supervisor do
  @moduledoc """
  Supervisor for WebSocket connections.

  Manages multiple WebSocket connections for different streams.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Main ticker stream for popular pairs
      {DataCollector.WebSocket.Client, streams: ["btcusdt@ticker", "ethusdt@ticker", "bnbusdt@ticker"]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
