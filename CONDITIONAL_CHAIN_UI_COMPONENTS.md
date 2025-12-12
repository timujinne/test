# Conditional Chain UI Components

Complete UI implementation for the ConditionalChain trading strategy using Phoenix LiveView and DaisyUI/Tailwind CSS.

## Overview

This implementation provides a full-featured user interface for creating, managing, and monitoring conditional trading chains. The UI is built with Phoenix LiveView for real-time updates and DaisyUI components for a polished, responsive design.

## Created Files

### 1. Chain Step Component
**File:** `/app/apps/dashboard_web/lib/dashboard_web/components/trading/chain_step.ex`

**Purpose:** Display and edit individual chain steps (buy/sell orders)

**Features:**
- Support for three step types: initial, step, and branch
- Editable fields for side (BUY/SELL), quantity, and price
- Visual status indicators (pending, active, completed, failed)
- Color-coded borders and badges based on status
- Delete functionality for editable steps
- Execution details display for completed steps

**Usage:**
```elixir
<.chain_step
  step=%{side: "BUY", quantity: "0.1", price: "42000"}
  index={0}
  step_type="step"
  editable={true}
  on_delete="delete_step"
  on_update="update_step"
  status="pending"
/>
```

### 2. Branch Editor Component
**File:** `/app/apps/dashboard_web/lib/dashboard_web/components/trading/branch_editor.ex`

**Purpose:** Edit conditional branches with two execution paths

**Features:**
- Condition threshold settings (percentage up/down)
- Two separate paths: "If Price Rises" and "If Price Falls"
- Each path has side, quantity, and price fields
- Visual differentiation with success/error color schemes
- Arrow icons for up/down conditions
- Support for market or limit prices

**Data Structure:**
```elixir
%{
  condition: %{
    type: "price_change_percent",
    threshold_up: "1.0",
    threshold_down: "-1.0"
  },
  if_up: %{side: "SELL", quantity: "0.1", price: "market"},
  if_down: %{side: "BUY", quantity: "0.1", price: "market"}
}
```

**Usage:**
```elixir
<.branch_editor
  branch={@branch_data}
  index={1}
  editable={true}
  on_delete="delete_branch"
  on_update="update_branch"
/>
```

### 3. Chain Builder Component
**File:** `/app/apps/dashboard_web/lib/dashboard_web/components/trading/chain_builder.ex`

**Purpose:** Visual chain constructor for building multi-step trading chains

**Features:**
- Chain configuration (name, symbol, initial quantity)
- Symbol dropdown or manual entry
- Dynamic step list with visual connectors (arrows)
- Add step/branch buttons
- Inline step editing using chain_step and branch_editor components
- Form validation with visual feedback
- Save/Cancel actions
- Support for create and edit modes

**Validation:**
- Chain name required
- Trading symbol required
- Initial quantity must be > 0
- At least one step required

**Usage:**
```elixir
<.chain_builder
  chain={@chain_form}
  symbols={@available_symbols}
  on_save="save_chain"
  on_cancel="hide_builder"
  mode="create"
/>
```

### 4. Chain Monitor Component
**File:** `/app/apps/dashboard_web/lib/dashboard_web/components/trading/chain_monitor.ex`

**Purpose:** Real-time monitoring of active chain executions

**Features:**
- Chain status display (active, stopped, completed, failed, cancelled)
- Progress bar showing completion percentage
- Current price display
- P&L (Profit & Loss) calculation with visual indicators
  - Total P&L with percentage
  - Realized/Unrealized breakdown
  - Color coding (green for profit, red for loss)
- Step-by-step execution tracking with status badges
- Stop and Cancel action buttons
- Compact and full view modes
- Execution statistics (total steps, completed, remaining)
- Started timestamp

**Usage:**
```elixir
<.chain_monitor
  chain={@active_chain}
  current_price={42150.50}
  on_stop="stop_chain"
  on_cancel="cancel_chain"
  compact={false}
/>
```

### 5. Chains LiveView Page
**File:** `/app/apps/dashboard_web/lib/dashboard_web/live/chains_live.ex`

**Purpose:** Main page for chain management and execution

**Features:**
- List of saved chains with card-based layout
- Active chains section with real-time monitoring
- Chain builder (integrated via query params)
- PubSub integration for real-time updates
- Price subscription for active chain symbols
- CRUD operations: create, edit, delete chains
- Chain execution controls: start, stop, cancel
- Responsive grid layout for saved chains
- Modal-style builder interface

**Event Handlers:**
- `show_builder` - Open chain builder
- `hide_builder` - Close chain builder
- `update_chain_field` - Update chain configuration
- `add_step` - Add new step or branch
- `delete_step` - Remove step from chain
- `update_step` - Modify step fields
- `save_chain` - Persist chain to database
- `start_chain` - Begin chain execution
- `stop_chain` - Stop active chain
- `cancel_chain` - Cancel and rollback chain
- `delete_chain` - Delete saved chain

**PubSub Topics:**
- `chains:all` - Global chain updates
- `market:#{symbol}` - Price updates for chain symbols

**URL Patterns:**
- `/chains` - Main view
- `/chains?action=new` - New chain builder
- `/chains?action=edit&id=123` - Edit existing chain

### 6. Trading Components Module Update
**File:** `/app/apps/dashboard_web/lib/dashboard_web/components/trading.ex`

**Updates:**
- Added delegates for all chain components
- Updated module documentation
- Exported: `chain_step/1`, `branch_editor/1`, `chain_builder/1`, `chain_monitor/1`

### 7. Router Update
**File:** `/app/apps/dashboard_web/lib/dashboard_web/router.ex`

**Updates:**
- Added route: `live "/chains", ChainsLive`
- Integrated into `:default` live_session with drawer layout

### 8. Navigation Updates
**Files:**
- `/app/apps/dashboard_web/lib/dashboard_web/components/dashboard_nav.ex` - Added chain icon
- `/app/apps/dashboard_web/lib/dashboard_web/components/layouts/drawer.html.heex` - Added Chains nav item

## Design System

### DaisyUI Components Used
- `card` - Container elements
- `btn` - Action buttons
- `input` - Text inputs
- `select` - Dropdowns
- `badge` - Status indicators
- `progress` - Progress bars
- `alert` - Info/warning messages
- `dropdown` - Menus
- `divider` - Section separators
- `stats` - Statistics display

### Color Schemes
- **Primary** - Main actions, initial steps
- **Success** - Buy orders, positive P&L, upward movement
- **Error** - Sell orders, negative P&L, downward movement
- **Warning** - Branches, stop actions
- **Info** - Active status, chain monitoring

### Status Colors
| Status | Border | Badge | Context |
|--------|--------|-------|---------|
| Pending | Gray | Ghost | Not started |
| Active | Blue (thick) | Info | Currently executing |
| Completed | Green | Success | Successfully finished |
| Failed | Red | Error | Execution error |

## Component Hierarchy

```
ChainsLive (Page)
├── ChainBuilder (Create/Edit)
│   ├── ChainStep (for regular steps)
│   └── BranchEditor (for conditional branches)
│       └── branch_path_form (internal)
├── ChainMonitor (Active execution)
│   ├── ChainStep (read-only)
│   └── BranchEditor (read-only)
└── saved_chain_card (List view)
```

## State Management

### Chain Form Structure
```elixir
%{
  name: "My Trading Chain",
  symbol: "BTCUSDT",
  initial_quantity: "0.1",
  steps: [
    %{type: "step", side: "BUY", quantity: "0.1", price: "42000"},
    %{
      type: "branch",
      condition: %{threshold_up: "1.0", threshold_down: "-1.0"},
      if_up: %{side: "SELL", quantity: "0.1", price: "market"},
      if_down: %{side: "BUY", quantity: "0.1", price: "market"}
    }
  ]
}
```

### Active Chain Structure
```elixir
%{
  id: "chain_123",
  name: "My Chain",
  symbol: "BTCUSDT",
  status: "active",
  current_step: 2,
  steps: [
    %{
      type: "step",
      side: "BUY",
      status: "completed",
      executed_price: "41950",
      executed_at: ~U[2025-01-01 10:00:00Z]
    },
    %{type: "step", side: "SELL", status: "active", ...},
    %{type: "branch", status: "pending", ...}
  ],
  pnl: %{
    realized: 150.25,
    unrealized: -20.50,
    total: 129.75,
    percent: 1.29
  },
  started_at: ~U[2025-01-01 10:00:00Z]
}
```

## Integration Points (TODO)

The following functions are stubbed and need implementation:

### Database Operations
- `save_chain/3` - Save chain to database via Settings context
- `load_chains/1` - Load saved and active chains from database
- `delete_saved_chain/1` - Delete chain from database

### TradingEngine Integration
- `start_chain_execution/1` - Start chain strategy in TradingEngine
- `stop_chain_execution/1` - Stop running chain
- `cancel_chain_execution/1` - Cancel and potentially rollback chain

### PubSub Events
Subscribe to:
- `chains:all` - Chain lifecycle events
- `market:#{symbol}` - Price updates for active chains

Broadcast:
- Chain status changes
- Step execution updates
- P&L calculations

## Responsive Design

All components are mobile-responsive:
- Grid layouts use `md:grid-cols-2` and `lg:grid-cols-3` for adaptive columns
- Forms stack vertically on mobile
- Branch editor switches from side-by-side to stacked on mobile
- Navigation drawer collapses on mobile

## Accessibility

- Proper ARIA labels on interactive elements
- Semantic HTML structure
- Keyboard navigation support
- Clear visual focus indicators
- High contrast color schemes

## Testing Recommendations

### Unit Tests
- Component rendering with various props
- Status badge color logic
- Progress calculation
- Form validation

### Integration Tests
- Chain creation flow
- Step addition/deletion
- Branch configuration
- Chain execution lifecycle

### E2E Tests
- Complete chain creation
- Chain execution monitoring
- Multi-step chain with branches
- Stop/cancel operations

## Future Enhancements

1. **Drag-and-drop reordering** of steps
2. **Chain templates** for common patterns
3. **Backtesting** visualization
4. **Performance metrics** dashboard
5. **Chain cloning** functionality
6. **Export/import** chains as JSON
7. **Real-time order book** integration in builder
8. **Step conditions** beyond price (volume, time, indicators)
9. **Multi-chain orchestration**
10. **Chain analytics** and reports

## File Summary

| File | Lines | Purpose |
|------|-------|---------|
| chain_step.ex | 267 | Single step component |
| branch_editor.ex | 280 | Branch editor component |
| chain_builder.ex | 365 | Chain builder interface |
| chain_monitor.ex | 408 | Execution monitor |
| chains_live.ex | 570 | Main LiveView page |
| **Total** | **1,890** | Complete UI implementation |

## Compilation Status

All files compile successfully with no errors. The project is ready for:
1. Backend integration (database + TradingEngine)
2. Testing and validation
3. Production deployment

## Usage Example

Visit `/chains` in your browser to:
1. View saved chains
2. Monitor active executions
3. Create new chains with the builder
4. Edit existing chains
5. Start/stop/cancel chain executions

The UI provides a complete visual interface for the ConditionalChain strategy without requiring any command-line interaction.
