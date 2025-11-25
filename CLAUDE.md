# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Elixir/Phoenix umbrella application for Binance cryptocurrency trading with automated strategies and real-time monitoring.

**Tech Stack**: Elixir 1.14+, Phoenix 1.7+ with LiveView, PostgreSQL 15+ with TimescaleDB

## Umbrella Structure

```
apps/
├── shared_data/      # Ecto schemas, Repo, PubSub, Vault (encryption)
├── data_collector/   # Binance REST/WebSocket client, rate limiting
├── trading_engine/   # Strategies, Trader GenServers, risk management
└── dashboard_web/    # Phoenix LiveView UI
```

**Dependency flow**: `shared_data` ← `data_collector` ← `trading_engine` ← `dashboard_web`

## Development Commands

```bash
# Start services
make start              # Docker: postgres, redis, dev container
make server             # Phoenix server (port 4000)
make server-iex         # With IEx console

# Testing
mix test                           # All tests
mix test apps/trading_engine/test  # Single app tests
mix test apps/trading_engine/test/trading_engine/strategies/naive_test.exs  # Single file
mix test --cover                   # With coverage

# Code quality
make check              # format + credo + tests
make format             # Format code
make credo              # Linter
make dialyzer           # Static analysis

# Database
make db-create          # Create database
make db-migrate         # Run migrations
make db-reset           # Drop and recreate

# Generate migration (run from umbrella root)
mix ecto.gen.migration add_field_to_table -r SharedData.Repo
```

## Architecture

### PubSub Topics (SharedData.PubSub)

All apps share `BinanceSystem.PubSub`. Use `SharedData.PubSub.subscribe/1` and `broadcast/2`.

| Topic | Messages | Publishers | Subscribers |
|-------|----------|------------|-------------|
| `market:#{symbol}` | `{:ticker, data}`, `{:trade, data}` | BinanceWebSocket | MarketData, Trader, TradingLive |
| `order_updates` | `{:execution_report, data}` | BinanceWebSocket | Trader, TradingLive |
| `balance_updates` | `{:balance_update, data}` | BinanceWebSocket | PortfolioLive |

### Trading Strategy Pattern

Strategies implement `TradingEngine.Strategy` behaviour (`apps/trading_engine/lib/trading_engine/strategy.ex`):

```elixir
@callback init(config) :: {:ok, state}
@callback on_tick(market_data, state) :: {action, state}
@callback on_execution(execution, state) :: {action, state}
# action: {:place_order, params} | {:cancel_order, order_id} | :noop
```

**Existing strategies**: `Naive`, `Grid`, `DCA` in `apps/trading_engine/lib/trading_engine/strategies/`

### Process Architecture

- **One Trader GenServer per account** - Registered via `TradingEngine.TraderRegistry`
- **AccountSupervisor** - DynamicSupervisor managing Trader processes
- **Lookup pattern**: `{:via, Registry, {TradingEngine.TraderRegistry, account_id}}`

### Key Modules

| Module | Purpose |
|--------|---------|
| `SharedData.Vault` | Cloak encryption for API keys |
| `SharedData.Accounts` | Account CRUD operations |
| `DataCollector.BinanceClient` | REST API calls |
| `DataCollector.BinanceWebSocket` | WebSocket streams |
| `DataCollector.RateLimiter` | API rate limit handling |
| `DataCollector.CircuitBreaker` | Failure protection |
| `TradingEngine.RiskManager` | Order validation |
| `TradingEngine.PositionTracker` | Position tracking |

## Environment Variables

Required in `.env` (copy from `.env.example`):

```bash
BINANCE_API_KEY=xxx
BINANCE_SECRET_KEY=xxx
BINANCE_BASE_URL=https://testnet.binance.vision  # Use testnet for dev
CLOAK_KEY=xxx                                     # 32-byte base64: make gen-secret
SECRET_KEY_BASE=xxx                               # mix phx.gen.secret
DATABASE_URL=postgres://postgres:postgres@localhost:5432/binance_trading_dev
```

## Custom Skills

Skills in `.claude/skills/` provide specialized knowledge. Key skills:
- `elixir/genserver.md` - GenServer patterns
- `phoenix/liveview.md` - LiveView components
- `database/migration.md` - Ecto migrations
- `trading-strategies.md` - Strategy implementation
- `binance-api.md` - Binance API integration

## Important Patterns

### GenServer Timeouts (SharedData.Config)

Use configured timeouts instead of defaults:
```elixir
GenServer.call(pid, msg, Config.timeout(:fast))   # Simple reads
GenServer.call(pid, msg, Config.timeout(:api))    # External API calls
```

### Encryption

API credentials are encrypted with Cloak (AES-256-GCM):
```elixir
# In schema
field :api_key, SharedData.Encrypted.Binary
field :secret_key, SharedData.Encrypted.Binary
```

### Type Specs

Use types from `SharedData.Types`:
```elixir
@spec place_order(Types.account_id(), Types.order_params()) :: Types.result(Types.order())
```
