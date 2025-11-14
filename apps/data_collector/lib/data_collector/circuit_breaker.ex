defmodule DataCollector.CircuitBreaker do
  @moduledoc """
  Circuit Breaker implementation for Binance API calls.

  Implements the Circuit Breaker pattern to prevent cascading failures
  when the Binance API is unavailable or slow.

  ## States

  - `:closed` - Normal operation, requests flow through
  - `:open` - Too many failures, rejecting requests immediately
  - `:half_open` - Testing if service recovered, allowing limited requests

  ## Configuration

  From `SharedData.Config.circuit_breaker/1`:
  - Threshold: 10 failures in 10 seconds opens circuit
  - Reset timeout: 60 seconds before trying again
  - Half-open requests: 3 successful requests closes circuit

  ## Usage

      # Wrap API calls
      CircuitBreaker.call(:binance_api, fn ->
        HTTPoison.get("https://api.binance.com/...")
      end)

  ## Returns

  - `{:ok, result}` - Call succeeded
  - `{:error, :circuit_open}` - Circuit is open, call rejected
  - `{:error, reason}` - Call failed for other reason
  """
  use GenServer
  require Logger

  alias SharedData.{Config, Types}

  @table_name :circuit_breaker_state

  # Client API

  @doc """
  Starts the Circuit Breaker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a function within the circuit breaker protection.

  ## Examples

      iex> CircuitBreaker.call(:binance_api, fn -> {:ok, "result"} end)
      {:ok, "result"}

      iex> CircuitBreaker.call(:binance_api, fn -> {:error, :timeout} end)
      {:error, :timeout}
  """
  @spec call(atom(), (() -> Types.result(any()))) :: Types.result(any())
  def call(circuit_name, fun) when is_atom(circuit_name) and is_function(fun, 0) do
    case get_state(circuit_name) do
      :closed ->
        execute_call(circuit_name, fun)

      :open ->
        {:error, :circuit_open}

      :half_open ->
        execute_call(circuit_name, fun)
    end
  end

  @doc """
  Gets the current state of a circuit.
  """
  @spec get_state(atom()) :: :closed | :open | :half_open
  def get_state(circuit_name) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, state, _failures, _last_failure_time, _opened_at}] ->
        check_state_transition(circuit_name, state)

      [] ->
        # Circuit doesn't exist yet, initialize it
        GenServer.cast(__MODULE__, {:initialize_circuit, circuit_name})
        :closed
    end
  end

  @doc """
  Resets a circuit to closed state.
  """
  @spec reset(atom()) :: :ok
  def reset(circuit_name) do
    GenServer.cast(__MODULE__, {:reset, circuit_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting #{__MODULE__}")

    # Create ETS table for circuit state
    table = :ets.new(@table_name, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:initialize_circuit, circuit_name}, state) do
    # Initialize circuit in closed state
    :ets.insert(@table_name, {circuit_name, :closed, 0, nil, nil})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:reset, circuit_name}, state) do
    :ets.insert(@table_name, {circuit_name, :closed, 0, nil, nil})
    Logger.info("Circuit #{circuit_name} manually reset to closed")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_success, circuit_name}, state) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, :half_open, _failures, _last_failure, _opened_at}] ->
        # In half-open state, success closes the circuit
        :ets.insert(@table_name, {circuit_name, :closed, 0, nil, nil})
        Logger.info("Circuit #{circuit_name} closed after successful test")

      [{^circuit_name, _state, _failures, _last_failure, _opened_at}] ->
        # In other states, just reset failure counter
        :ets.update_element(@table_name, circuit_name, {3, 0})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_failure, circuit_name}, state) do
    now = System.monotonic_time(:millisecond)
    threshold = Config.circuit_breaker(:threshold)
    window_ms = Config.circuit_breaker(:window_ms)

    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, current_state, failures, last_failure_time, _opened_at}] ->
        # Check if we're within the failure window
        within_window =
          last_failure_time && (now - last_failure_time) < window_ms

        new_failures =
          if within_window do
            failures + 1
          else
            1
          end

        # Should we open the circuit?
        if new_failures >= threshold and current_state == :closed do
          :ets.insert(@table_name, {circuit_name, :open, new_failures, now, now})

          Logger.warning("""
          Circuit #{circuit_name} opened
          Failures: #{new_failures} in #{window_ms}ms window
          Threshold: #{threshold}
          """)
        else
          :ets.update_element(@table_name, circuit_name, [
            {3, new_failures},
            {4, now}
          ])
        end

      [] ->
        # Initialize with first failure
        :ets.insert(@table_name, {circuit_name, :closed, 1, now, nil})
    end

    {:noreply, state}
  end

  # Private functions

  defp execute_call(circuit_name, fun) do
    try do
      result = fun.()
      handle_result(circuit_name, result)
    rescue
      error ->
        record_failure(circuit_name)
        {:error, {:exception, error}}
    end
  end

  defp handle_result(circuit_name, {:ok, _} = success) do
    record_success(circuit_name)
    success
  end

  defp handle_result(circuit_name, {:error, reason} = error) do
    if should_record_failure?(reason) do
      record_failure(circuit_name)
    end

    error
  end

  defp handle_result(circuit_name, other) do
    # Treat unexpected results as success
    record_success(circuit_name)
    {:ok, other}
  end

  # Determines if an error should count towards opening the circuit
  defp should_record_failure?("HTTP " <> status) when status >= "500", do: true
  defp should_record_failure?("HTTP 429" <> _), do: true  # Rate limit
  defp should_record_failure?(%HTTPoison.Error{}), do: true  # Network errors
  defp should_record_failure?(:timeout), do: true
  defp should_record_failure?({:exception, _}), do: true
  defp should_record_failure?(_), do: false  # Don't count client errors

  defp record_success(circuit_name) do
    GenServer.cast(__MODULE__, {:record_success, circuit_name})
  end

  defp record_failure(circuit_name) do
    GenServer.cast(__MODULE__, {:record_failure, circuit_name})
  end

  # Check if circuit should transition from open to half-open
  defp check_state_transition(circuit_name, :open) do
    case :ets.lookup(@table_name, circuit_name) do
      [{^circuit_name, :open, _failures, _last_failure, opened_at}] ->
        now = System.monotonic_time(:millisecond)
        reset_timeout = Config.circuit_breaker(:reset_ms)

        if now - opened_at >= reset_timeout do
          # Transition to half-open
          :ets.update_element(@table_name, circuit_name, {2, :half_open})
          Logger.info("Circuit #{circuit_name} transitioning from open to half-open")
          :half_open
        else
          :open
        end

      _ ->
        :open
    end
  end

  defp check_state_transition(_circuit_name, state), do: state
end
