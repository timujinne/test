# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Binance Trading System** is a production-ready cryptocurrency portfolio management system built with Elixir/Phoenix. It provides automated trading strategies, real-time monitoring, and multi-account management for Binance exchange.

### Architecture
- **Language**: Elixir 1.14+ with OTP 25+
- **Framework**: Phoenix 1.7+ with LiveView
- **Database**: PostgreSQL 15+ with TimescaleDB extension
- **Structure**: Umbrella application with 4 main apps:
  - `shared_data` - Common database schemas and Ecto Repo
  - `data_collector` - Binance API/WebSocket integration
  - `trading_engine` - Trading logic and strategies
  - `dashboard_web` - Phoenix LiveView UI

### Key Features
- Multiple Binance account management (via Sub-accounts)
- Real-time market data monitoring
- Automated trading strategies (Naive, Grid, DCA)
- Risk management and stop-loss mechanisms
- Portfolio tracking with P&L calculation
- AES-256-GCM encryption for API keys
- TimescaleDB for efficient time-series data storage

## Development Commands

### Quick Start
```bash
# Docker setup (recommended)
make start              # Start all services
make db-create          # Create database
make db-migrate         # Run migrations
make server             # Start Phoenix server

# Local setup
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

### Common Commands
```bash
# Development
make server             # Start Phoenix server
make server-iex         # Start with IEx console
make test               # Run tests
make check              # Full check (format + credo + tests)

# Database
make db-create          # Create database
make db-migrate         # Run migrations
make db-reset           # Reset database
make db-seed            # Seed test data

# Code Quality
make format             # Format code
make credo              # Run Credo linter
make dialyzer           # Static analysis

# Docker
make start              # Start containers
make stop               # Stop containers
make logs               # View all logs
make logs-app           # View app logs only
```

Full command list: `make help`

## Custom Agents

### General Proposal Agent

The project includes a custom `general-proposal` agent for executing any development tasks with full access to skills.

**Location**: `.claude/agents/general-proposal.md`

**Purpose**: Universal task executor that can handle any development work by leveraging all available skills and tools.

**Usage**:
```
# Explicit invocation
> Use the general-proposal agent to [task description]

# Automatic delegation (Claude decides when to use)
> [Describe your task and Claude may automatically delegate to the agent]
```

**Capabilities**:
- Full access to all custom skills in `.claude/skills/`
- Backend development (Elixir, Phoenix, GenServers)
- Database operations (migrations, schemas, TimescaleDB)
- Frontend development (LiveView, JavaScript)
- API integrations and testing
- DevOps tasks

**Model**: Sonnet 4.5 (claude-sonnet-4-5-20250929)

## Custom Skills

Skills are stored in `.claude/skills/` directory. See `SKILLS_GUIDE.md` and `.claude/skills/README.md` for details on creating and using skills.

**Current Skills**:
- `example-skill` - Template for creating new skills
- 20+ custom skills for Elixir/Phoenix/Binance development

**Planned Skills**:
- `elixir-genserver` - Generate GenServer modules with tests
- `phoenix-liveview` - Create LiveView components
- `db-migration` - Database migration generator
- `binance-test` - Binance API test helpers

## Development Workflow

1. Use `/agents` command to manage custom agents
2. Invoke skills with `> Use [skill-name] skill for [task]`
3. Let the general-proposal agent handle complex multi-step tasks
4. Skills and agents work together to streamline development

## Key Directories

```
binance_system/
├── apps/
│   ├── shared_data/         # Common DB schemas and Ecto Repo
│   ├── data_collector/      # Binance API/WebSocket integration
│   ├── trading_engine/      # Trading logic and strategies
│   └── dashboard_web/       # Phoenix LiveView UI
├── .claude/
│   ├── agents/              # Custom agent definitions
│   └── skills/              # Custom skill definitions
├── config/                  # Application configuration
├── monitoring/              # Grafana/Prometheus configs
└── priv/                    # Static files and migrations
```

## Configuration

### Environment Variables

Required environment variables (see `.env.example`):

```bash
# Binance API
BINANCE_API_KEY=your_api_key
BINANCE_SECRET_KEY=your_secret_key
BINANCE_BASE_URL=https://testnet.binance.vision  # Use testnet for dev

# Security
CLOAK_KEY=your_base64_encoded_key  # For API key encryption
SECRET_KEY_BASE=your_phoenix_secret

# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/binance_trading_dev
```

### Getting Binance API Keys

**Development (Testnet)**:
1. Go to https://testnet.binance.vision/
2. Login via GitHub
3. Get API Key and Secret Key
4. Use testnet endpoints

**Production**:
1. Go to https://www.binance.com/en/my/settings/api-management
2. Create new API key
3. Configure permissions (Enable Reading + Spot & Margin Trading)
4. Set IP whitelist for security
5. **NEVER** enable withdrawal permissions

## Security Best Practices

### API Key Management
- Always use testnet for development
- Store keys in environment variables (never commit to git)
- Enable IP whitelist for production keys
- Regularly rotate API keys
- Use AES-256-GCM encryption in database (via Cloak)

### Multi-Account Warning
Binance Terms of Service (Section 20.1.l) prohibit multiple personal accounts.

**Legal methods**:
1. **Sub-accounts** - For VIP1+ users (up to 200 sub-accounts)
2. **Corporate accounts** - Separate legal entities

## Testing

```bash
# Run all tests
mix test

# With coverage
mix test --cover

# Specific test file
mix test test/trading_engine/strategies/naive_test.exs

# Watch mode
mix test.watch
```

### Test Types
- **Unit tests** - Isolated module tests
- **Integration tests** - Component interaction tests
- **Property-based tests** - Using StreamData
- **Feature tests** - End-to-end LiveView tests

## Architecture Details

### OTP Supervision Tree
- One GenServer per trading account for isolation
- Fault-tolerant design with supervision trees
- Automatic process restart on failures

### Real-time Updates
- Phoenix Channels for WebSocket communication
- LiveView for reactive UI updates
- Binance WebSocket streams for market data

### Data Storage
- PostgreSQL for relational data
- TimescaleDB for time-series market data
- Continuous aggregates for pre-calculated statistics
- ETS for in-memory caching

## Monitoring and Observability

- **Phoenix LiveDashboard** - Real-time application metrics
- **Telemetry** - Custom metrics and events
- **Grafana** (optional) - Advanced monitoring dashboards
- **Prometheus** (optional) - Metrics collection
- Audit logging for all trading operations

## Documentation

### Project Documentation
- [README.md](README.md) - Main project documentation
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - Detailed implementation plan
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) - Development guidelines
- [AUDIT_REPORT.md](AUDIT_REPORT.md) - Code audit report

### External Resources
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Binance API Docs](https://binance-docs.github.io/apidocs/)

## Common Development Patterns

### Creating a New Trading Strategy
1. Create module in `apps/trading_engine/lib/trading_engine/strategies/`
2. Implement `init/1`, `handle_tick/2`, and `handle_order/2` callbacks
3. Add tests in `apps/trading_engine/test/strategies/`
4. Register strategy in configuration

### Adding a LiveView Component
1. Create component in `apps/dashboard_web/lib/dashboard_web/live/`
2. Use `use DashboardWeb, :live_view`
3. Implement `mount/3` and `handle_event/3` callbacks
4. Add routes in `router.ex`

### Database Migrations
```bash
# Create migration
cd apps/shared_data
mix ecto.gen.migration add_field_to_table

# Edit migration file in priv/repo/migrations/
# Run migration
mix ecto.migrate
```

## Important Notes

- Always test trading strategies in paper trading mode first
- Monitor rate limits to avoid Binance API restrictions
- Use sub-accounts for legitimate multi-account management
- Enable 2FA on Binance account for security
- Never commit API keys or secrets to git
- Review BUGFIXES_PHASE7.md for known critical bug fixes

## Troubleshooting

### Common Issues

**Database connection error**:
```bash
# Check PostgreSQL is running
make start  # For Docker setup

# Recreate database
make db-reset
```

**Asset compilation error**:
```bash
cd apps/dashboard_web/assets
npm install
cd ../../..
mix phx.server
```

**API key encryption error**:
```bash
# Generate new Cloak key
make gen-secret
# Add to .env as CLOAK_KEY
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This system is provided "as is" without any warranties. Cryptocurrency trading carries high risks. Use at your own risk. Authors are not responsible for financial losses.

**Always test strategies in paper trading mode before using real funds!**
