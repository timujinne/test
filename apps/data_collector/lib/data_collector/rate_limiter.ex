defmodule DataCollector.RateLimiter do
  @moduledoc """
  GenServer for managing Binance API rate limits.

  Implements sliding window algorithm to prevent 429 errors.
  """
  use GenServer
  require Logger

  alias SharedData.Config

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check_limit(weight \\ 1) do
    # Fast timeout for rate limit check
    GenServer.call(__MODULE__, {:check_limit, weight}, Config.timeout(:fast))
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting #{__MODULE__}")
    
    state = %{
      requests: [],
      max_requests: 1200,  # Binance limit per minute
      window_size: 60_000  # 1 minute in milliseconds
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:check_limit, weight}, _from, state) do
    now = System.monotonic_time(:millisecond)
    window_start = now - state.window_size
    
    # Remove old requests outside the window
    recent_requests = Enum.filter(state.requests, fn {timestamp, _} -> 
      timestamp > window_start 
    end)
    
    current_weight = Enum.sum(Enum.map(recent_requests, fn {_, w} -> w end))
    
    if current_weight + weight <= state.max_requests do
      new_requests = [{now, weight} | recent_requests]
      {:reply, :ok, %{state | requests: new_requests}}
    else
      wait_time = calculate_wait_time(recent_requests, state.window_size)
      {:reply, {:wait, wait_time}, %{state | requests: recent_requests}}
    end
  end

  defp calculate_wait_time(requests, window_size) do
    case List.last(requests) do
      {timestamp, _} -> 
        timestamp + window_size - System.monotonic_time(:millisecond)
      nil -> 
        0
    end
  end
end
