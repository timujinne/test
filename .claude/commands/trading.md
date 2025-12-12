Load the trading-system skill for working with the TradingEngine umbrella application.

Use `/skill trading-system` to load comprehensive documentation for:

## Architecture
- Process supervision tree (StrategyManager, AccountSupervisor, Trader)
- Registry-based process lookup patterns
- Data flow: Market Data → Conditions → Strategy → Orders → Positions

## Public APIs
- **StrategyManager** - start/stop strategies, check running status
- **AccountCoordinator** - account summaries, risk limits, position aggregation
- **SharedPositionTracker** - position tracking, P&L calculation
- **PendingStrategiesManager** - start condition monitoring
- **StopConditionsMonitor** - stop condition monitoring
- **StrategyLoader** - strategy registration and lookup
- **ConditionEvaluator** - condition evaluation with AND/OR logic

## Strategies
- **Naive** - buy low/sell high based on percentage changes
- **Grid** - grid of limit orders above/below price
- **DCA** - periodic fixed-amount purchases
- **ConditionalChain** - sequential orders with branching

## Conditions
- **Start conditions**: price, time, volume
- **Stop conditions**: take_profit, stop_loss, max_daily_loss, time_stop

## PubSub Topics
- `strategy_updates` - lifecycle events
- `strategies:all` - for UI updates
- `market:#{symbol}` - ticker and trade data
- `order_updates` - execution reports
- `position_updates` - position changes

## Tools
- **Generator script**: Create new strategies with boilerplate
  ```bash
  python3 .claude/skills/trading-system/scripts/generate_strategy.py
  ```
- **IEx debugging**: Commands for inspecting running strategies
- **Workflow examples**: Step-by-step guides for common tasks

## Related Skills
- `binance-api` - Binance REST/WebSocket API integration
- `elixir-otp` - GenServer and supervision patterns
- `phoenix-liveview` - Building trading UI
