defmodule BinanceSystem do
  @moduledoc """
  BinanceSystem - Cryptocurrency Trading System

  A production-ready system for managing multiple Binance accounts
  with automated trading strategies using Elixir/Phoenix.

  ## Features

  - Multiple account management (via Sub-accounts)
  - Real-time market data monitoring
  - Automated trading strategies (Naive, Grid, DCA)
  - Risk management and stop-loss mechanisms
  - Portfolio tracking and P&L calculation
  - Historical data and analytics
  - Paper trading mode for testing

  ## Architecture

  This is the root module for the Binance Trading System.
  The actual functionality is split across multiple apps:

  - `SharedData` - Common database schemas and Ecto Repo
  - `DataCollector` - Binance API/WebSocket integration
  - `TradingEngine` - Trading logic and strategies
  - `DashboardWeb` - Phoenix LiveView interface

  ## Configuration

  See `config/` directory for configuration options.

  ## Getting Started

      # Install dependencies
      mix deps.get

      # Run tests
      mix test

      # Start application
      mix run --no-halt

  """

  @doc """
  Returns the version of the application.
  """
  def version do
    Application.spec(:binance_system, :vsn) |> to_string()
  end
end
