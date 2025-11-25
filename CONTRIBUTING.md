# Contributing to Binance Trading System

Thank you for your interest in contributing! This document provides guidelines and information for contributors.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## Getting Started

### Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- PostgreSQL 15+ with TimescaleDB
- Docker and Docker Compose (recommended)
- Git

### Development Setup

```bash
# 1. Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/binance_system.git
cd binance_system

# 2. Set up environment
cp .env.example .env
# Edit .env with your configuration

# 3. Start services
make start

# 4. Set up database
make db-create
make db-migrate

# 5. Run tests to verify setup
make test
```

## How to Contribute

### Reporting Bugs

Before creating a bug report:
1. Check existing [issues](https://github.com/timujinne/binance_system/issues)
2. Ensure you're using the latest version
3. Collect relevant information (logs, screenshots, steps to reproduce)

When creating a bug report, include:
- Clear, descriptive title
- Steps to reproduce the issue
- Expected vs actual behavior
- Environment details (Elixir version, OS, etc.)
- Relevant logs or error messages

### Suggesting Features

Feature requests are welcome! Please:
1. Check if the feature was already requested
2. Describe the use case and benefits
3. Consider if it fits the project scope

### Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following our coding standards
4. **Add tests** for new functionality
5. **Run checks** before committing:
   ```bash
   make check  # Runs format, credo, and tests
   ```
6. **Commit** with a clear message (see below)
7. **Push** to your fork
8. **Create a Pull Request** against `main`

## Coding Standards

### Elixir Style Guide

We follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide):

- Use 2-space indentation
- Max line length: 100 characters
- Use snake_case for functions and variables
- Use PascalCase for modules

### Code Formatting

All code must be formatted:
```bash
mix format
```

### Linting

Code should pass Credo checks:
```bash
mix credo --strict
```

### Type Specs

Add type specs for public functions:
```elixir
@spec calculate_pnl(Decimal.t(), Decimal.t()) :: Decimal.t()
def calculate_pnl(entry_price, current_price) do
  # ...
end
```

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, no code change
- `refactor`: Code restructuring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat(trading): add grid trading strategy

Implements basic grid trading with configurable levels.

Closes #123
```

```
fix(risk): correct decimal precision in position sizing

Fixes rounding errors in position calculations that could
lead to incorrect trade sizes.
```

## Testing

### Running Tests

```bash
# All tests
mix test

# With coverage
mix test --cover

# Specific app
mix test apps/trading_engine/test/

# Specific file
mix test apps/trading_engine/test/strategies/naive_test.exs

# Watch mode
mix test.watch
```

### Writing Tests

- Place tests in `apps/*/test/`
- Use `async: true` when tests don't share state
- Test both success and failure cases
- Cover edge cases and boundary conditions

Example:
```elixir
defmodule TradingEngine.Strategies.NaiveTest do
  use ExUnit.Case, async: true

  alias TradingEngine.Strategies.Naive

  describe "calculate_buy_price/2" do
    test "returns price below current by threshold" do
      # ...
    end

    test "handles nil input gracefully" do
      # ...
    end
  end
end
```

## Project Structure

```
binance_system/
├── apps/
│   ├── shared_data/       # Database schemas and encryption
│   ├── data_collector/    # Binance API integration
│   ├── trading_engine/    # Trading logic and strategies
│   └── dashboard_web/     # Phoenix LiveView UI
├── config/                # Configuration files
├── docs/                  # Additional documentation
└── monitoring/            # Grafana/Prometheus configs
```

## Pull Request Review

PRs are reviewed for:
- Code quality and style
- Test coverage
- Documentation updates
- Security implications
- Performance considerations

## Questions?

- Open an [issue](https://github.com/timujinne/binance_system/issues)
- Email: timujeen@gmail.com

---

Thank you for contributing!
