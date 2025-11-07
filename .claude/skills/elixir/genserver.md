---
name: elixir-genserver
description: Generate Elixir GenServer module with supervision tree and tests
tags: elixir, genserver, otp, supervision
---

# Generate GenServer Module

This skill generates a complete GenServer module with tests and supervision tree integration.

## Step 1: Gather Requirements

Ask the user for:
1. **Module name** (e.g., `TradingEngine.OrderManager`)
2. **App name** (e.g., `trading_engine`)
3. **Initial state structure** (e.g., map with specific keys)
4. **Main functionality** description

## Step 2: Create GenServer Module

Create file at: `apps/{app}/lib/{path}/{module_name}.ex`

```elixir
defmodule {ModuleName} do
  use GenServer
  require Logger

  @moduledoc """
  {Description of what this GenServer does}

  ## Examples

      iex> {:ok, pid} = {ModuleName}.start_link([])
      iex> {ModuleName}.get_state()
      %{}

  """

  # Client API

  @doc """
  Starts the GenServer.

  ## Options

    * `:name` - registered name for the process (default: module name)
    * `:initial_state` - initial state (default: %{})

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\\\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current state of the GenServer.
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Synchronous operation example.
  """
  @spec sync_operation(term()) :: {:ok, term()} | {:error, term()}
  def sync_operation(data) do
    GenServer.call(__MODULE__, {:sync_operation, data})
  end

  @doc """
  Asynchronous operation example.
  """
  @spec async_operation(term()) :: :ok
  def async_operation(data) do
    GenServer.cast(__MODULE__, {:async_operation, data})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting #{__MODULE__}")

    initial_state = Keyword.get(opts, :initial_state, %{})

    # Schedule periodic work if needed
    # Process.send_after(self(), :periodic_work, 5_000)

    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:sync_operation, data}, _from, state) do
    # Implement your logic here
    case process_data(data) do
      {:ok, result} -> {:reply, {:ok, result}, Map.put(state, :last_result, result)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:async_operation, data}, state) do
    # Implement async logic
    Logger.debug("Processing async operation: #{inspect(data)}")
    {:noreply, Map.update(state, :operations, 1, &(&1 + 1))}
  end

  @impl true
  def handle_info(:periodic_work, state) do
    # Periodic work logic
    Logger.debug("Executing periodic work")

    # Schedule next execution
    Process.send_after(self(), :periodic_work, 5_000)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("Terminating #{__MODULE__}: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp process_data(data) do
    # Implement data processing
    {:ok, data}
  end
end
```

## Step 3: Create Test File

Create file at: `apps/{app}/test/{path}/{module_name}_test.exs`

```elixir
defmodule {ModuleName}Test do
  use ExUnit.Case, async: true

  alias {ModuleName}

  describe "start_link/1" do
    test "starts the GenServer successfully" do
      assert {:ok, pid} = {ModuleName}.start_link(name: :test_server)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom initial state" do
      initial_state = %{count: 0, data: []}
      assert {:ok, pid} = {ModuleName}.start_link(
        name: :test_server_custom,
        initial_state: initial_state
      )

      assert {ModuleName}.get_state() == initial_state
      GenServer.stop(pid)
    end
  end

  describe "get_state/0" do
    setup do
      {:ok, pid} = {ModuleName}.start_link(name: :test_get_state)
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "returns current state", %{pid: _pid} do
      state = {ModuleName}.get_state()
      assert is_map(state)
    end
  end

  describe "sync_operation/1" do
    setup do
      {:ok, pid} = {ModuleName}.start_link(name: :test_sync)
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "processes data successfully", %{pid: _pid} do
      assert {:ok, result} = {ModuleName}.sync_operation("test_data")
      assert result == "test_data"
    end
  end

  describe "async_operation/1" do
    setup do
      {:ok, pid} = {ModuleName}.start_link(name: :test_async)
      on_exit(fn -> GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "processes async operation", %{pid: _pid} do
      assert :ok = {ModuleName}.async_operation("async_data")
      # Give it time to process
      Process.sleep(10)
      state = {ModuleName}.get_state()
      assert Map.get(state, :operations, 0) >= 1
    end
  end
end
```

## Step 4: Add to Supervision Tree

Update `apps/{app}/lib/{app}/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... existing children ...
    {ModuleName}, []},
  ]

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Step 5: Run Tests

```bash
# Run tests for specific file
mix test apps/{app}/test/{path}/{module_name}_test.exs

# Run all tests
mix test

# With coverage
mix test --cover
```

## Step 6: Usage Examples

```elixir
# Start in IEx
iex> {:ok, pid} = {ModuleName}.start_link([])

# Get state
iex> {ModuleName}.get_state()

# Sync operation
iex> {ModuleName}.sync_operation("my_data")

# Async operation
iex> {ModuleName}.async_operation("async_data")

# Stop
iex> GenServer.stop(pid)
```

## Additional Considerations

1. **Error Handling**: Add proper error handling for edge cases
2. **Timeouts**: Add timeouts to GenServer.call/3 calls if needed
3. **Telemetry**: Consider adding telemetry events for monitoring
4. **Documentation**: Ensure all public functions have @doc and @spec
5. **Logging**: Use Logger for important events and errors

## Supervision Strategies

Choose appropriate restart strategy:
- `:temporary` - never restarted
- `:transient` - restarted only if terminates abnormally
- `:permanent` - always restarted (default)

Example with custom restart:
```elixir
{
  {ModuleName}, []},
  restart: :transient,
  shutdown: 5000
}
```
