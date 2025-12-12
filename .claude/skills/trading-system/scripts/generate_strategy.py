#!/usr/bin/env python3
"""
Trading Strategy Generator

Generates boilerplate code for new trading strategies in the TradingEngine umbrella app.

Usage:
    python3 generate_strategy.py                           # Interactive mode
    python3 generate_strategy.py --name momentum           # With name
    python3 generate_strategy.py --name momentum --type tick  # Full params
    python3 generate_strategy.py --list-types              # Show strategy types

Strategy Types:
    tick    - Reacts to market data ticks (like Naive, Grid)
    timer   - Periodic execution (like DCA)
    hybrid  - Both ticks and timers
"""

import argparse
import os
import re
import sys
from datetime import datetime
from pathlib import Path


# Templates for different strategy types

TICK_STRATEGY_TEMPLATE = '''defmodule TradingEngine.Strategies.{module_name} do
  @moduledoc """
  {description}

  ## Configuration

  ```elixir
  %{{
    "symbol" => "BTCUSDT",
    # Add your config fields here
  }}
  ```
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def requirements(_config) do
    %{{
      ticks: true,       # Subscribe to market data
      timers: [],        # No timers needed
      executions: true   # Subscribe to execution reports
    }}
  end

  @impl true
  def init(config) do
    state = %{{
      symbol: config["symbol"],
      # Add your state fields here
      last_price: nil,
      position: nil
    }}

    Logger.info("{module_name}: Initialized for #{{state.symbol}}")
    {{:ok, state}}
  end

  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])

    # TODO: Implement your tick logic here
    # Return {{:place_order, order_params}, new_state}} or {{:noop, new_state}}

    new_state = %{{state | last_price: current_price}}
    {{:noop, new_state}}
  end

  @impl true
  def on_execution(execution, state) do
    case execution["x"] do
      "TRADE" ->
        side = execution["S"]
        price = Decimal.new(execution["L"])
        qty = Decimal.new(execution["l"])

        Logger.info("{module_name}: #{{side}} #{{qty}} at #{{price}}")

        # TODO: Update your state based on execution
        new_state = state

        {{:noop, new_state}}

      _ ->
        {{:noop, state}}
    end
  end

  # Private functions

  # TODO: Add your helper functions here
end
'''

TIMER_STRATEGY_TEMPLATE = '''defmodule TradingEngine.Strategies.{module_name} do
  @moduledoc """
  {description}

  ## Configuration

  ```elixir
  %{{
    "symbol" => "BTCUSDT",
    "interval_ms" => 3600000,  # 1 hour
    # Add your config fields here
  }}
  ```
  """
  @behaviour TradingEngine.Strategy

  require Logger

  alias DataCollector.BinanceClient

  @impl true
  def requirements(config) do
    interval_ms = config["interval_ms"] || 3_600_000

    %{{
      ticks: false,           # No tick subscription needed
      timers: [interval_ms],  # Timer interval
      executions: true        # Subscribe to execution reports
    }}
  end

  @impl true
  def init(config) do
    interval_ms = config["interval_ms"] || 3_600_000

    state = %{{
      symbol: config["symbol"],
      interval_ms: interval_ms,
      # Add your state fields here
      execution_count: 0
    }}

    Logger.info("{module_name}: Initialized for #{{state.symbol}}, interval=#{{div(interval_ms, 1000)}}s")
    {{:ok, state}}
  end

  @impl true
  def on_timer(_ref, state) do
    # Fetch current price via API
    case get_current_price(state.symbol) do
      {{:ok, current_price}} ->
        Logger.info("{module_name}: Timer fired at price #{{current_price}}")

        # TODO: Implement your timer logic here
        # Return {{:place_order, order_params}, new_state}} or {{:noop, new_state}}

        {{:noop, state}}

      {{:error, reason}} ->
        Logger.error("{module_name}: Failed to fetch price: #{{inspect(reason)}}")
        {{:noop, state}}
    end
  end

  @impl true
  def on_tick(_market_data, state) do
    # Not used in timer-based strategy
    {{:noop, state}}
  end

  @impl true
  def on_execution(execution, state) do
    case execution["x"] do
      "TRADE" ->
        side = execution["S"]
        price = Decimal.new(execution["L"])
        qty = Decimal.new(execution["l"])

        Logger.info("{module_name}: #{{side}} #{{qty}} at #{{price}}")

        new_state = %{{state | execution_count: state.execution_count + 1}}
        {{:noop, new_state}}

      _ ->
        {{:noop, state}}
    end
  end

  # Private functions

  defp get_current_price(symbol) do
    case BinanceClient.get_ticker_price(symbol) do
      {{:ok, %{{"price" => price_str}}}} ->
        {{:ok, Decimal.new(price_str)}}

      {{:error, reason}} ->
        {{:error, reason}}
    end
  end
end
'''

HYBRID_STRATEGY_TEMPLATE = '''defmodule TradingEngine.Strategies.{module_name} do
  @moduledoc """
  {description}

  Hybrid strategy that uses both ticks and timers.

  ## Configuration

  ```elixir
  %{{
    "symbol" => "BTCUSDT",
    "timer_interval_ms" => 60000,  # 1 minute
    # Add your config fields here
  }}
  ```
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def requirements(config) do
    timer_interval = config["timer_interval_ms"] || 60_000

    %{{
      ticks: true,              # Subscribe to market data
      timers: [timer_interval], # Periodic timer
      executions: true          # Subscribe to execution reports
    }}
  end

  @impl true
  def init(config) do
    timer_interval = config["timer_interval_ms"] || 60_000

    state = %{{
      symbol: config["symbol"],
      timer_interval: timer_interval,
      # Add your state fields here
      last_price: nil,
      position: nil,
      tick_count: 0,
      timer_count: 0
    }}

    Logger.info("{module_name}: Initialized for #{{state.symbol}}")
    {{:ok, state}}
  end

  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])

    new_state = %{{state |
      last_price: current_price,
      tick_count: state.tick_count + 1
    }}

    # TODO: Implement your tick logic here

    {{:noop, new_state}}
  end

  @impl true
  def on_timer(_ref, state) do
    Logger.debug("{module_name}: Timer fired, tick_count=#{{state.tick_count}}")

    new_state = %{{state | timer_count: state.timer_count + 1}}

    # TODO: Implement your timer logic here
    # Use state.last_price from tick updates

    {{:noop, new_state}}
  end

  @impl true
  def on_execution(execution, state) do
    case execution["x"] do
      "TRADE" ->
        side = execution["S"]
        price = Decimal.new(execution["L"])
        qty = Decimal.new(execution["l"])

        Logger.info("{module_name}: #{{side}} #{{qty}} at #{{price}}")

        # TODO: Update your state based on execution

        {{:noop, state}}

      _ ->
        {{:noop, state}}
    end
  end
end
'''

TEST_TEMPLATE = '''defmodule TradingEngine.Strategies.{module_name}Test do
  use ExUnit.Case, async: true

  alias TradingEngine.Strategies.{module_name}

  describe "init/1" do
    test "initializes with valid config" do
      config = %{{
        "symbol" => "BTCUSDT"
      }}

      assert {{:ok, state}} = {module_name}.init(config)
      assert state.symbol == "BTCUSDT"
    end
  end

  describe "requirements/1" do
    test "returns correct requirements" do
      config = %{{"symbol" => "BTCUSDT"}}
      requirements = {module_name}.requirements(config)

      assert is_boolean(requirements.ticks)
      assert is_list(requirements.timers)
      assert is_boolean(requirements.executions)
    end
  end

  describe "on_tick/2" do
    test "handles market data" do
      {{:ok, state}} = {module_name}.init(%{{"symbol" => "BTCUSDT"}})

      market_data = %{{
        "c" => "45000.00",
        "v" => "1000.5"
      }}

      {{action, _new_state}} = {module_name}.on_tick(market_data, state)
      assert action in [:noop, {{:place_order, _}}]
    end
  end

  describe "on_execution/2" do
    test "handles trade execution" do
      {{:ok, state}} = {module_name}.init(%{{"symbol" => "BTCUSDT"}})

      execution = %{{
        "x" => "TRADE",
        "S" => "BUY",
        "L" => "45000.00",
        "l" => "0.001"
      }}

      {{action, _new_state}} = {module_name}.on_execution(execution, state)
      assert action == :noop
    end
  end
end
'''


def to_module_name(name: str) -> str:
    """Convert snake_case or kebab-case to PascalCase."""
    # Replace hyphens with underscores
    name = name.replace('-', '_')
    # Split by underscores and capitalize each part
    parts = name.split('_')
    return ''.join(part.capitalize() for part in parts)


def to_file_name(name: str) -> str:
    """Convert name to snake_case file name."""
    # Replace hyphens with underscores
    name = name.replace('-', '_')
    # Convert camelCase to snake_case
    name = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', name)
    name = re.sub('([a-z0-9])([A-Z])', r'\1_\2', name)
    return name.lower()


def get_project_root() -> Path:
    """Find the project root (contains mix.exs)."""
    current = Path.cwd()
    while current != current.parent:
        if (current / 'mix.exs').exists():
            return current
        current = current.parent
    return Path.cwd()


def get_strategies_dir(project_root: Path) -> Path:
    """Get the strategies directory."""
    return project_root / 'apps' / 'trading_engine' / 'lib' / 'trading_engine' / 'strategies'


def get_tests_dir(project_root: Path) -> Path:
    """Get the tests directory."""
    return project_root / 'apps' / 'trading_engine' / 'test' / 'trading_engine' / 'strategies'


def get_strategy_loader_path(project_root: Path) -> Path:
    """Get the strategy_loader.ex path."""
    return project_root / 'apps' / 'trading_engine' / 'lib' / 'trading_engine' / 'strategy_loader.ex'


def generate_strategy(name: str, strategy_type: str, description: str, project_root: Path) -> dict:
    """Generate strategy files."""
    module_name = to_module_name(name)
    file_name = to_file_name(name)

    # Select template
    templates = {
        'tick': TICK_STRATEGY_TEMPLATE,
        'timer': TIMER_STRATEGY_TEMPLATE,
        'hybrid': HYBRID_STRATEGY_TEMPLATE
    }

    template = templates.get(strategy_type, TICK_STRATEGY_TEMPLATE)

    # Generate content
    strategy_content = template.format(
        module_name=module_name,
        description=description
    )

    test_content = TEST_TEMPLATE.format(module_name=module_name)

    # Paths
    strategies_dir = get_strategies_dir(project_root)
    tests_dir = get_tests_dir(project_root)

    strategy_path = strategies_dir / f'{file_name}.ex'
    test_path = tests_dir / f'{file_name}_test.exs'

    return {
        'strategy_path': strategy_path,
        'strategy_content': strategy_content,
        'test_path': test_path,
        'test_content': test_content,
        'module_name': module_name,
        'file_name': file_name,
        'loader_entry': f'    "{file_name}" => TradingEngine.Strategies.{module_name}'
    }


def update_strategy_loader(project_root: Path, file_name: str, module_name: str) -> bool:
    """Add new strategy to StrategyLoader."""
    loader_path = get_strategy_loader_path(project_root)

    if not loader_path.exists():
        print(f"Warning: StrategyLoader not found at {loader_path}")
        return False

    content = loader_path.read_text()

    # Check if already registered
    if f'"{file_name}"' in content:
        print(f"Strategy '{file_name}' already registered in StrategyLoader")
        return True

    # Find the @strategies map and add entry
    # Look for pattern: @strategies %{...}
    pattern = r'(@strategies %\{[^}]+)'
    match = re.search(pattern, content, re.DOTALL)

    if match:
        old_map = match.group(1)
        # Add new entry before the closing brace
        new_entry = f',\n    "{file_name}" => TradingEngine.Strategies.{module_name}'
        new_map = old_map.rstrip() + new_entry
        new_content = content.replace(old_map, new_map)

        loader_path.write_text(new_content)
        print(f"Added '{file_name}' to StrategyLoader")
        return True
    else:
        print("Warning: Could not find @strategies map in StrategyLoader")
        return False


def interactive_mode() -> dict:
    """Interactive prompts for strategy generation."""
    print("\n=== Trading Strategy Generator ===\n")

    # Name
    while True:
        name = input("Strategy name (e.g., momentum, mean_reversion): ").strip()
        if name and re.match(r'^[a-z][a-z0-9_-]*$', name):
            break
        print("Invalid name. Use lowercase letters, numbers, underscores, or hyphens.")

    # Type
    print("\nStrategy types:")
    print("  1. tick   - Reacts to market data (like Naive, Grid)")
    print("  2. timer  - Periodic execution (like DCA)")
    print("  3. hybrid - Both ticks and timers")

    while True:
        type_input = input("\nSelect type [1/2/3] or name: ").strip()
        type_map = {'1': 'tick', '2': 'timer', '3': 'hybrid'}
        strategy_type = type_map.get(type_input, type_input)
        if strategy_type in ['tick', 'timer', 'hybrid']:
            break
        print("Invalid type. Choose 1, 2, 3 or tick/timer/hybrid.")

    # Description
    description = input("\nBrief description: ").strip() or f"{to_module_name(name)} trading strategy."

    return {
        'name': name,
        'type': strategy_type,
        'description': description
    }


def main():
    parser = argparse.ArgumentParser(
        description='Generate trading strategy boilerplate code',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--name', '-n', help='Strategy name (snake_case)')
    parser.add_argument('--type', '-t', choices=['tick', 'timer', 'hybrid'],
                       default='tick', help='Strategy type')
    parser.add_argument('--description', '-d', help='Strategy description')
    parser.add_argument('--project-root', '-p', help='Project root path')
    parser.add_argument('--list-types', action='store_true', help='List strategy types')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be generated')
    parser.add_argument('--no-loader', action='store_true', help='Skip updating StrategyLoader')
    parser.add_argument('--no-test', action='store_true', help='Skip generating test file')

    args = parser.parse_args()

    if args.list_types:
        print("""
Strategy Types:

  tick    Reacts to market data ticks. Use for strategies that need
          real-time price updates to make decisions.
          Examples: Naive, Grid, momentum

  timer   Periodic execution on a schedule. Fetches price via API
          when timer fires. More efficient for time-based strategies.
          Examples: DCA, rebalancing

  hybrid  Both tick subscriptions and timers. Use when you need
          real-time data AND periodic actions.
          Examples: trailing stop with timeout, adaptive strategies
""")
        return 0

    # Get parameters
    if args.name:
        params = {
            'name': args.name,
            'type': args.type,
            'description': args.description or f"{to_module_name(args.name)} trading strategy."
        }
    else:
        params = interactive_mode()

    # Find project root
    if args.project_root:
        project_root = Path(args.project_root)
    else:
        project_root = get_project_root()

    print(f"\nProject root: {project_root}")

    # Generate
    result = generate_strategy(
        params['name'],
        params['type'],
        params['description'],
        project_root
    )

    print(f"\n=== Generated Files ===")
    print(f"Strategy: {result['strategy_path']}")
    if not args.no_test:
        print(f"Test:     {result['test_path']}")
    print(f"Module:   TradingEngine.Strategies.{result['module_name']}")

    if args.dry_run:
        print("\n=== Strategy Content (dry-run) ===")
        print(result['strategy_content'])
        return 0

    # Confirm
    confirm = input("\nGenerate files? [Y/n]: ").strip().lower()
    if confirm and confirm != 'y':
        print("Cancelled.")
        return 1

    # Create directories if needed
    result['strategy_path'].parent.mkdir(parents=True, exist_ok=True)
    if not args.no_test:
        result['test_path'].parent.mkdir(parents=True, exist_ok=True)

    # Write files
    if result['strategy_path'].exists():
        overwrite = input(f"\n{result['strategy_path']} exists. Overwrite? [y/N]: ").strip().lower()
        if overwrite != 'y':
            print("Skipped strategy file.")
        else:
            result['strategy_path'].write_text(result['strategy_content'])
            print(f"Created: {result['strategy_path']}")
    else:
        result['strategy_path'].write_text(result['strategy_content'])
        print(f"Created: {result['strategy_path']}")

    if not args.no_test:
        if result['test_path'].exists():
            overwrite = input(f"{result['test_path']} exists. Overwrite? [y/N]: ").strip().lower()
            if overwrite != 'y':
                print("Skipped test file.")
            else:
                result['test_path'].write_text(result['test_content'])
                print(f"Created: {result['test_path']}")
        else:
            result['test_path'].write_text(result['test_content'])
            print(f"Created: {result['test_path']}")

    # Update StrategyLoader
    if not args.no_loader:
        update_strategy_loader(project_root, result['file_name'], result['module_name'])

    print(f"""
=== Next Steps ===

1. Edit the generated strategy file:
   {result['strategy_path']}

2. Implement your trading logic in:
   - on_tick/2   (for market data handling)
   - on_timer/2  (for periodic actions, if using timers)
   - on_execution/2 (for handling order fills)

3. Add your config fields to init/1

4. Run tests:
   mix test apps/trading_engine/test/trading_engine/strategies/{result['file_name']}_test.exs

5. Test in IEx:
   config = %{{"symbol" => "BTCUSDT"}}
   {{:ok, state}} = TradingEngine.Strategies.{result['module_name']}.init(config)
""")

    return 0


if __name__ == '__main__':
    sys.exit(main())
