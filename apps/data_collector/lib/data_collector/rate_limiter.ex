defmodule DataCollector.RateLimiter do
  @moduledoc """
  Rate limiter to respect Binance API rate limits.

  Binance has different rate limits for different endpoints:
  - Request weight limits
  - Order rate limits
  - Raw request limits
  """

  use GenServer
  require Logger

  @limits %{
    # Binance weight limits (per minute)
    weight: {1200, 60_000},
    # Order limits (per 10 seconds)
    order: {100, 10_000},
    # Raw request limits (per minute)
    raw_requests: {6000, 60_000},
    # Market data limits (more generous)
    market_data: {2400, 60_000}
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    state = %{
      weight: {0, :os.system_time(:millisecond)},
      order: {0, :os.system_time(:millisecond)},
      raw_requests: {0, :os.system_time(:millisecond)},
      market_data: {0, :os.system_time(:millisecond)}
    }

    {:ok, state}
  end

  @doc """
  Check if we can make a request of the given type.
  Returns :ok if allowed, {:error, :rate_limited} otherwise.
  """
  def check_rate_limit(type) do
    GenServer.call(__MODULE__, {:check_rate_limit, type})
  end

  def handle_call({:check_rate_limit, type}, _from, state) do
    {limit, window} = @limits[type]
    {count, timestamp} = Map.get(state, type, {0, :os.system_time(:millisecond)})
    now = :os.system_time(:millisecond)

    cond do
      now - timestamp > window ->
        # Window expired, reset counter
        new_state = Map.put(state, type, {1, now})
        {:reply, :ok, new_state}

      count < limit ->
        # Within limits, increment counter
        new_state = Map.put(state, type, {count + 1, timestamp})
        {:reply, :ok, new_state}

      true ->
        # Rate limited
        wait_time = window - (now - timestamp)
        Logger.warning("Rate limit reached for #{type}, need to wait #{wait_time}ms")
        {:reply, {:error, :rate_limited}, state}
    end
  end
end
