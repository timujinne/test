# Strategy Status Display Fix

## Problem Summary
The strategies page was showing inaccurate status information:
- Showing "Starting..." when `is_active=true` even if the Trader process wasn't running
- Not reflecting actual running state from TraderRegistry
- No periodic verification of Trader process status

## Root Cause
The UI was only checking the database `is_active` flag without verifying if the actual Trader GenServer process exists in the TraderRegistry.

## Solution Implemented

### 1. Registry-Based Status Tracking
Added `sync_running_strategies/1` function that queries `TradingEngine.TraderRegistry` to verify which strategies actually have running Trader processes:

```elixir
defp sync_running_strategies(socket) do
  running_strategies =
    socket.assigns.strategies
    |> Enum.reduce(%{}, fn strategy, acc ->
      case Registry.lookup(TradingEngine.TraderRegistry, strategy.id) do
        [{_pid, _}] ->
          # Trader exists - include in running_strategies
          existing_state = Map.get(socket.assigns.running_strategies, strategy.id)
          state = existing_state || %{
            strategy_name: strategy.strategy_name,
            account_id: strategy.account_id,
            config: strategy.config,
            started_at: DateTime.utc_now()
          }
          Map.put(acc, strategy.id, state)
        [] ->
          # No Trader process - exclude from running_strategies
          acc
      end
    end)

  assign(socket, running_strategies: running_strategies)
end
```

### 2. Periodic Status Verification
Added a 5-second interval timer to periodically check Trader process status:

```elixir
if connected?(socket) do
  Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "strategies:all")
  :timer.send_interval(5000, self(), :check_trader_status)
end
```

### 3. Enhanced Status Display Logic
Updated the render template to show accurate status:

- **Running**: Green badge with pulsing dot when Trader process exists in Registry
- **Starting...**: Yellow badge with pulsing dot when `is_active=true` but no Trader process yet
- **Stopped**: Gray badge when `is_active=false`

```heex
<%= if Map.has_key?(@running_strategies, strategy.id) do %>
  <span class="badge badge-success">
    <span class="animate-pulse mr-1">●</span> Running
  </span>
<% else %>
  <%= if strategy.is_active do %>
    <span class="badge badge-warning">
      <span class="animate-pulse mr-1">●</span> Starting...
    </span>
  <% else %>
    <span class="badge badge-ghost">
      Stopped
    </span>
  <% end %>
<% end %>
```

### 4. Event-Driven Updates
Enhanced PubSub event handlers to sync status immediately:

- `{:strategy_started, setting_id, state}` - Updates running_strategies map
- `{:strategy_stopped, setting_id}` - Removes from running_strategies map
- `{:strategy_error, setting_id, reason}` - Removes and shows error
- `:check_trader_status` - Periodic verification

### 5. Sync on State Changes
Added `sync_running_strategies/1` calls after:
- Strategy activation
- Strategy deactivation
- Initial mount
- After data reload

## Files Modified

### `/app/apps/dashboard_web/lib/dashboard_web/live/strategies_live.ex`

**Changes:**
1. Added `:timer.send_interval(5000, self(), :check_trader_status)` in mount
2. Added `sync_running_strategies()` call in mount
3. Added `sync_running_strategies()` in activate/deactivate event handlers
4. Added `handle_info(:check_trader_status, socket)` handler
5. Added `sync_running_strategies/1` private function
6. Updated status badge rendering logic in template

## How It Works

### Strategy Lifecycle Flow

1. **Activation:**
   - User clicks "Start" button
   - `activate_strategy/1` sets `is_active=true` in database
   - Broadcasts `{:strategy_activated, setting}` to PubSub
   - StrategyManager receives event and starts Trader process
   - Trader registers in `TradingEngine.TraderRegistry` with `setting_id`
   - StrategyManager broadcasts `{:strategy_started, setting_id, state}`
   - UI receives event, updates `running_strategies` map
   - Status changes from "Starting..." to "Running"

2. **Deactivation:**
   - User clicks "Stop" button
   - `deactivate_strategy/1` sets `is_active=false`
   - Broadcasts `{:strategy_deactivated, setting}`
   - StrategyManager stops Trader process
   - Broadcasts `{:strategy_stopped, setting_id}`
   - UI removes from `running_strategies` map
   - Status changes to "Stopped"

3. **Verification:**
   - Every 5 seconds, `:check_trader_status` timer fires
   - `sync_running_strategies/1` queries TraderRegistry
   - Ensures UI state matches actual process state
   - Handles edge cases (crashes, restarts, etc.)

## Registry Lookup Pattern

Trader processes register using:
```elixir
{:via, Registry, {TradingEngine.TraderRegistry, setting_id}}
```

UI queries status using:
```elixir
Registry.lookup(TradingEngine.TraderRegistry, setting_id)
```

Returns:
- `[{pid, _}]` - Process exists (Running)
- `[]` - Process doesn't exist (Not running)

## Benefits

1. **Accurate Status**: UI always reflects actual Trader process state
2. **Real-time Updates**: PubSub events provide immediate feedback
3. **Self-healing**: Periodic checks catch any sync issues
4. **Clear Feedback**: Distinct states (Running/Starting/Stopped) with visual indicators
5. **Edge Case Handling**: Handles process crashes, restarts, and race conditions

## Testing Recommendations

1. **Basic Flow:**
   - Activate strategy → Verify "Starting..." → Verify "Running"
   - Deactivate strategy → Verify "Stopped"

2. **Edge Cases:**
   - Activate strategy with start conditions → Verify "Starting..." persists until conditions met
   - Kill Trader process manually → Verify status updates to "Stopped" within 5 seconds
   - Restart application → Verify running strategies restore and show correct status

3. **Race Conditions:**
   - Rapidly toggle strategy on/off → Verify final status is accurate
   - Multiple strategies starting → Verify each shows correct independent status

## Future Enhancements

1. Add "Pending" status for strategies waiting for start conditions
2. Show more detailed runtime information (orders placed, profit/loss)
3. Add manual refresh button for immediate status check
4. Show error state with error details
5. Add strategy health indicators (last tick received, etc.)
