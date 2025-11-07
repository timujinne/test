---
name: elixir-otp
description: Comprehensive guide for building fault-tolerant Elixir applications using OTP patterns. This skill should be used when developing systems with GenServers, Supervisors, process communication, Registry patterns, or any concurrent/distributed Elixir architecture requiring reliability and scalability.
---

# Elixir OTP Patterns

This skill provides expert guidance for building production-grade Elixir applications using OTP (Open Telecom Platform) principles and patterns.

## When to Use This Skill

Use this skill when working with:
- GenServer implementations for stateful processes
- Supervision trees and fault tolerance strategies
- Process communication and isolation patterns
- Registry and process discovery
- Dynamic supervision and process management
- Distributed Elixir applications
- Concurrent processing patterns

## Core OTP Concepts

### GenServer Patterns

GenServer is the foundation for building stateful processes in Elixir. Use GenServer when process needs to:
- Maintain internal state
- Handle synchronous (call) and asynchronous (cast) requests
- Perform cleanup on termination
- Implement timeout behaviors

**Basic GenServer template:**

```elixir
defmodule MyApp.Worker do
  use GenServer
  require Logger

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def update_state(new_value) do
    GenServer.cast(__MODULE__, {:update, new_value})
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    initial_state = Keyword.get(opts, :initial_value, %{})
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:update, new_value}, state) do
    new_state = Map.put(state, :value, new_value)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:periodic_work, state) do
    # Schedule next work
    Process.send_after(self(), :periodic_work, 5_000)
    {:noreply, state}
  end
end
```

**Key GenServer callbacks:**
- `init/1` - Initialize state, return `{:ok, state}` or `{:ok, state, timeout}`
- `handle_call/3` - Synchronous requests, return `{:reply, response, new_state}`
- `handle_cast/2` - Asynchronous requests, return `{:noreply, new_state}`
- `handle_info/2` - Handle all other messages (timers, monitors, etc.)
- `terminate/2` - Cleanup before process shutdown

### Supervision Strategies

Supervisors automatically restart child processes when they crash, implementing the "let it crash" philosophy.

**Supervision strategies:**

1. **:one_for_one** - Restart only the failed child
   - Use for: Independent workers (e.g., per-account traders, isolated tasks)
   - Example: Multiple database connection pools

2. **:one_for_all** - Restart all children when any child fails
   - Use for: Interdependent processes that can't function independently
   - Example: Trading engine where OrderBook, PositionManager, and RiskEngine depend on each other

3. **:rest_for_one** - Restart failed child and all children started after it
   - Use for: Sequential dependencies
   - Example: WebSocket connection → Stream processor → Data store

**Supervisor template:**

```elixir
defmodule MyApp.MainSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Static children
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Registry, keys: :unique, name: MyApp.Registry},
      
      # GenServers
      {MyApp.StateManager, []},
      {MyApp.DataCollector, []},
      
      # Dynamic supervisor for workers
      {DynamicSupervisor, strategy: :one_for_one, name: MyApp.WorkerSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**Restart strategies:**
- `:permanent` - Always restart (default for critical processes)
- `:temporary` - Never restart (for one-off tasks)
- `:transient` - Restart only on abnormal exit (for workers that may complete successfully)

### Process Communication Patterns

**1. Direct messaging (send/receive):**

```elixir
# Sender
send(pid, {:message, data})

# Receiver (in GenServer)
def handle_info({:message, data}, state) do
  # Process message
  {:noreply, state}
end
```

**2. Phoenix.PubSub (recommended for distributed systems):**

```elixir
# Subscribe
Phoenix.PubSub.subscribe(MyApp.PubSub, "topic:subtopic")

# Broadcast
Phoenix.PubSub.broadcast(MyApp.PubSub, "topic:subtopic", {:event, data})

# In GenServer
def handle_info({:event, data}, state) do
  # Handle broadcasted event
  {:noreply, state}
end
```

**3. Via tuples with Registry:**

```elixir
# Register process
{:via, Registry, {MyApp.Registry, {:worker, account_id}}}

# Look up and send message
case Registry.lookup(MyApp.Registry, {:worker, account_id}) do
  [{pid, _}] -> GenServer.call(pid, :get_state)
  [] -> {:error, :not_found}
end
```

### Registry for Process Discovery

Registry enables O(1) process lookups by key, essential for managing many dynamic processes.

**Setup:**

```elixir
# In application.ex
{Registry, keys: :unique, name: MyApp.Registry}
```

**Usage pattern:**

```elixir
defmodule MyApp.AccountManager do
  def start_account(account_id, params) do
    spec = {MyApp.Account, account_id: account_id, params: params}
    DynamicSupervisor.start_child(MyApp.AccountSupervisor, spec)
  end

  def get_account(account_id) do
    case Registry.lookup(MyApp.Registry, {:account, account_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def stop_account(account_id) do
    with {:ok, pid} <- get_account(account_id) do
      DynamicSupervisor.terminate_child(MyApp.AccountSupervisor, pid)
    end
  end
end

defmodule MyApp.Account do
  use GenServer

  def start_link(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    name = {:via, Registry, {MyApp.Registry, {:account, account_id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    {:ok, %{account_id: account_id, data: %{}}}
  end
end
```

### Dynamic Supervision

DynamicSupervisor manages processes that start and stop dynamically during runtime.

**Setup:**

```elixir
# In application.ex
{DynamicSupervisor, strategy: :one_for_one, name: MyApp.WorkerSupervisor}

# Starting children dynamically
def start_worker(id, params) do
  spec = {MyApp.Worker, [id: id, params: params]}
  DynamicSupervisor.start_child(MyApp.WorkerSupervisor, spec)
end

# Stopping children
def stop_worker(pid) do
  DynamicSupervisor.terminate_child(MyApp.WorkerSupervisor, pid)
end

# Listing all children
def list_workers do
  DynamicSupervisor.which_children(MyApp.WorkerSupervisor)
end
```

## Advanced Patterns

### Process-per-Entity Pattern

Isolate each entity (user, account, connection) in its own process for fault isolation and concurrent processing.

```elixir
# Supervisor manages pool of entity processes
defmodule MyApp.EntitySupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_entity(entity_id, params) do
    spec = {MyApp.Entity, Map.put(params, :entity_id, entity_id)}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

# Each entity is isolated GenServer
defmodule MyApp.Entity do
  use GenServer

  def start_link(params) do
    entity_id = Map.fetch!(params, :entity_id)
    name = via_tuple(entity_id)
    GenServer.start_link(__MODULE__, params, name: name)
  end

  defp via_tuple(entity_id) do
    {:via, Registry, {MyApp.Registry, {:entity, entity_id}}}
  end

  def init(params) do
    # Each entity has isolated state
    {:ok, %{
      entity_id: params.entity_id,
      state: :initialized,
      data: %{}
    }}
  end
end
```

## Best Practices

1. **Keep GenServer callbacks fast**: Offload heavy work to separate processes or use Task.async
2. **Use Registry for process discovery**: Avoid storing PIDs in state (they become stale)
3. **Design supervision trees carefully**: Group interdependent processes under one_for_all
4. **Implement backpressure**: Use GenStage or Flow for handling high-volume events
5. **Monitor external dependencies**: Use health checks and circuit breakers
6. **Log strategically**: Log process starts, stops, and state transitions
7. **Test supervision**: Use `Process.exit/2` in tests to verify restart behavior

## Common Pitfalls

1. **Storing PIDs in state**: Use Registry or monitor processes instead
2. **Tight coupling**: Use PubSub for loose coupling between processes
3. **Synchronous bottlenecks**: Prefer cast over call when response not needed
4. **Memory leaks**: Always cleanup subscriptions and monitors in terminate/2
5. **Wrong supervision strategy**: Choose strategy based on process dependencies

## Debugging Tools

- **:observer.start()** - Visual process tree and system metrics
- **Process.info(pid)** - Get process details
- **:sys.get_state(pid)** - Inspect GenServer state
- **:sys.trace(pid, true)** - Trace GenServer messages
- **Supervisor.which_children(supervisor_pid)** - List supervised processes
