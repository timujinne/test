# Strategy Status Reference Guide

## Quick Status Check

To understand a strategy's current state, check three sources:

1. **Database (`settings` table)**: `is_active` field
2. **TraderRegistry**: Process existence via `Registry.lookup(TradingEngine.TraderRegistry, setting_id)`
3. **PubSub Events**: Real-time lifecycle messages on `"strategies:all"` topic

## Status States

| Status | Badge Color | is_active | Trader Process | Meaning |
|--------|-------------|-----------|----------------|---------|
| **Running** | Green (success) | `true` | Exists | Strategy is actively trading |
| **Starting...** | Yellow (warning) | `true` | Not yet | Strategy activated, waiting to start |
| **Stopped** | Gray (ghost) | `false` | N/A | Strategy is not active |

## Status Determination Logic

```elixir
# Check if Trader process exists
case Registry.lookup(TradingEngine.TraderRegistry, setting_id) do
  [{pid, _}] ->
    # Process found → Status: "Running"
    running = true

  [] ->
    # No process found
    if setting.is_active do
      # Status: "Starting..." (process starting or waiting for conditions)
      running = false
    else
      # Status: "Stopped"
      running = false
    end
end
```

## PubSub Events Flow

### Strategy Activation
```
User clicks "Start"
  ↓
LiveView: handle_event("activate_strategy")
  ↓
Database: UPDATE settings SET is_active=true
  ↓
PubSub.broadcast("strategy_updates", {:strategy_activated, setting})
  ↓
StrategyManager: handle_info({:strategy_activated, setting})
  ↓
Start Conditions Check:
  - Has conditions? → PendingStrategiesManager
  - No conditions? → Start Trader immediately
  ↓
Trader Process Started
  ↓
Trader registers: Registry.register(TraderRegistry, setting_id)
  ↓
PubSub.broadcast("strategies:all", {:strategy_started, setting_id, state})
  ↓
LiveView: handle_info({:strategy_started, setting_id, state})
  ↓
UI updates: running_strategies[setting_id] = state
  ↓
Status badge changes: "Starting..." → "Running"
```

### Strategy Deactivation
```
User clicks "Stop"
  ↓
LiveView: handle_event("deactivate_strategy")
  ↓
Database: UPDATE settings SET is_active=false
  ↓
PubSub.broadcast("strategy_updates", {:strategy_deactivated, setting})
  ↓
StrategyManager: handle_info({:strategy_deactivated, setting})
  ↓
Stop Trader Process
  ↓
PubSub.broadcast("strategies:all", {:strategy_stopped, setting_id})
  ↓
LiveView: handle_info({:strategy_stopped, setting_id})
  ↓
UI updates: running_strategies[setting_id] = nil
  ↓
Status badge changes: "Running" → "Stopped"
```

## Verification Mechanisms

### 1. Mount-time Sync
On LiveView connection:
```elixir
socket
|> load_data()          # Load strategies from database
|> sync_running_strategies()  # Verify against Registry
```

### 2. Periodic Sync (Every 5 seconds)
```elixir
:timer.send_interval(5000, self(), :check_trader_status)

def handle_info(:check_trader_status, socket) do
  socket = sync_running_strategies(socket)
  {:noreply, socket}
end
```

### 3. Event-driven Sync
After every state change:
```elixir
socket
|> load_data()
|> sync_running_strategies()
```

## Registry Lookup Examples

### Check if Strategy is Running
```elixir
case Registry.lookup(TradingEngine.TraderRegistry, setting_id) do
  [{pid, _}] ->
    IO.puts("Strategy running with PID: #{inspect(pid)}")
  [] ->
    IO.puts("Strategy not running")
end
```

### Get All Running Traders
```elixir
Registry.select(TradingEngine.TraderRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
# Returns: [{setting_id, pid, value}, ...]
```

### Get Trader State
```elixir
case Registry.lookup(TradingEngine.TraderRegistry, setting_id) do
  [{pid, _}] ->
    state = TradingEngine.Trader.get_state(setting_id)
    IO.inspect(state)
  [] ->
    {:error, :not_running}
end
```

## Common Issues & Solutions

### Issue: Status shows "Starting..." indefinitely

**Possible Causes:**
1. Strategy has start conditions that aren't met
2. Trader failed to start but error wasn't reported
3. Process crashed during startup

**Debug Steps:**
```elixir
# 1. Check database
setting = SharedData.Settings.get_setting(setting_id)
IO.inspect(setting.is_active)  # Should be true
IO.inspect(setting.config["start_conditions"])  # Check conditions

# 2. Check Registry
Registry.lookup(TradingEngine.TraderRegistry, setting_id)
# Empty list [] means process isn't running

# 3. Check StrategyManager
TradingEngine.StrategyManager.is_running?(setting_id)

# 4. Check PendingStrategiesManager
# If has start conditions, may be pending
```

### Issue: Status shows "Running" but no trades

**Possible Causes:**
1. Strategy logic not triggering
2. Market data not flowing
3. Risk manager blocking orders

**Debug Steps:**
```elixir
# 1. Get Trader state
state = TradingEngine.Trader.get_state(setting_id)
IO.inspect(state.strategy_state)

# 2. Check subscriptions
IO.inspect(state.subscribed_to_ticks)

# 3. Check market data
# Subscribe to ticker and verify messages
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")
```

### Issue: Status doesn't update after restart

**Cause:** Running strategies not restored after application restart

**Solution:**
StrategyManager automatically restores active strategies on startup:
```elixir
# In StrategyManager.init/1
Process.send_after(self(), :restore_active_strategies, 1000)
```

## Testing Commands

### IEx Testing
```elixir
# Start IEx
iex -S mix phx.server

# List all strategies
SharedData.Settings.list_all_settings()

# Check specific strategy status
setting_id = "your-setting-id"
Registry.lookup(TradingEngine.TraderRegistry, setting_id)

# Get running strategies from StrategyManager
TradingEngine.StrategyManager.get_running_strategies()

# Manually start/stop strategy
TradingEngine.StrategyManager.start_strategy(setting_id)
TradingEngine.StrategyManager.stop_strategy(setting_id)

# Check LiveView assigns (when connected)
# In browser console:
# liveSocket.getSocket().channels[0].join().receive("ok", data => console.log(data))
```

## UI Implementation Details

### Running Strategies Map Structure
```elixir
%{
  "setting-id-1" => %{
    strategy_name: "naive",
    account_id: "account-id",
    config: %{...},
    started_at: ~U[2025-11-27 12:00:00Z]
  },
  "setting-id-2" => %{...}
}
```

### Status Badge Component
```heex
<%= if Map.has_key?(@running_strategies, strategy.id) do %>
  <!-- Green badge: Trader process confirmed in Registry -->
  <span class="badge badge-success">
    <span class="animate-pulse mr-1">●</span> Running
  </span>
  <%= if runtime_info = Map.get(@running_strategies, strategy.id) do %>
    <span class="text-xs text-base-content/50">
      Started <%= format_time_ago(runtime_info.started_at) %>
    </span>
  <% end %>
<% else %>
  <%= if strategy.is_active do %>
    <!-- Yellow badge: is_active=true but no process yet -->
    <span class="badge badge-warning">
      <span class="animate-pulse mr-1">●</span> Starting...
    </span>
  <% else %>
    <!-- Gray badge: is_active=false -->
    <span class="badge badge-ghost">
      Stopped
    </span>
  <% end %>
<% end %>
```

## Performance Considerations

### Registry Lookups
- O(1) lookup time
- Minimal overhead
- Safe to call frequently

### Periodic Sync
- Runs every 5 seconds
- Only queries strategies visible to user
- Negligible CPU impact

### PubSub Events
- Instant delivery
- No polling required
- Scales with Phoenix's PubSub

## Security Notes

1. **User Isolation**: Currently no user_id filtering (Phase 8 enhancement)
2. **Registry Access**: Read-only queries, safe for UI
3. **Process Control**: Only StrategyManager can start/stop Traders
4. **Data Validation**: All activation/deactivation goes through Settings context

## Related Files

- `/app/apps/dashboard_web/lib/dashboard_web/live/strategies_live.ex` - LiveView implementation
- `/app/apps/trading_engine/lib/trading_engine/strategy_manager.ex` - Process lifecycle
- `/app/apps/trading_engine/lib/trading_engine/trader.ex` - Individual Trader GenServer
- `/app/apps/trading_engine/lib/trading_engine/account_supervisor.ex` - Process supervision
- `/app/apps/trading_engine/lib/trading_engine/application.ex` - TraderRegistry setup
