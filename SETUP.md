# Binance Trading System - Setup Guide

This is an Elixir Umbrella project implementing a Binance trading system.

## Structure

The project consists of 4 main applications:

1. **shared_data** - Database schemas and Ecto repository
2. **data_collector** - Binance API integration and market data collection
3. **trading_engine** - Trading strategies and execution
4. **dashboard_web** - Phoenix LiveView web interface

## Prerequisites

- Elixir 1.14+
- PostgreSQL 15+
- Node.js 18+ (for Phoenix assets)
- Binance API keys (testnet recommended for development)

## Quick Start

### 1. Install Dependencies

```bash
# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies for Phoenix assets
cd apps/dashboard_web/assets && npm install
```

### 2. Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your credentials
```

Required environment variables:
- `BINANCE_API_KEY` - Your Binance API key
- `BINANCE_SECRET_KEY` - Your Binance secret key
- `CLOAK_KEY` - Encryption key for storing API credentials (generate with `openssl rand -base64 32`)
- `SECRET_KEY_BASE` - Phoenix secret key base
- `DATABASE_URL` - PostgreSQL connection URL

### 3. Setup Database

```bash
# Create and migrate the database
mix ecto.setup
```

### 4. Start the Application

```bash
# Start Phoenix server
cd apps/dashboard_web && mix phx.server

# Or start with IEx console
iex -S mix phx.server
```

Visit http://localhost:4000 to see the dashboard.

## Using Docker

```bash
# Start all services with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## Development

### Run Tests

```bash
mix test
```

### Format Code

```bash
mix format
```

### Check Code Quality

```bash
mix credo
```

## Project Status

This is a foundational implementation with:

✅ Complete Umbrella project structure
✅ Database schemas with encryption
✅ Binance API client with rate limiting
✅ Trading engine with GenServer architecture
✅ Phoenix LiveView dashboard (basic)
✅ Configuration for all environments

🚧 Pending (as per IMPLEMENTATION_PLAN.md):
- WebSocket integration for real-time market data
- Complete trading strategies implementation
- Full Phoenix LiveView UI components
- Database migrations
- Test coverage
- Additional features as per roadmap

## Next Steps

1. Review IMPLEMENTATION_PLAN.md for detailed development roadmap
2. Set up your Binance Testnet account at https://testnet.binance.vision/
3. Configure API keys in .env
4. Run database migrations (to be created)
5. Start implementing features per the plan

## Documentation

- Main README: [README.md](README.md)
- Implementation Plan: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
- Quick Start: [QUICKSTART.md](QUICKSTART.md)
- Docker Guide: [DOCKER_GUIDE.md](DOCKER_GUIDE.md)

## Support

For issues and questions, please refer to the main documentation or create an issue in the repository.
