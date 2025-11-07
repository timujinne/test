# Binance System - Umbrella Project

This is an Elixir Umbrella project for the Binance Trading System.

## Structure

- `apps/shared_data` - Database schemas and shared data structures
- `apps/data_collector` - Binance API integration and market data collection
- `apps/trading_engine` - Trading strategies and execution engine
- `apps/dashboard_web` - Phoenix web interface

## Getting Started

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Run tests
mix test

# Start Phoenix server (dashboard)
cd apps/dashboard_web && mix phx.server
```

## Documentation

See the main [README.md](README.md) for full documentation.
