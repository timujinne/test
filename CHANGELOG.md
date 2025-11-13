# Changelog

All notable changes to the Binance Trading System will be documented in this file.

## [Unreleased]

### Added
- Complete Elixir Umbrella project structure
- Database migrations for all schemas (users, api_credentials, orders, trades, balances, settings)
- TimescaleDB support for time-series trade data
- Phoenix LiveView pages (Dashboard, Trading, Portfolio, Settings)
- Core UI components and layouts
- WebSocket client for real-time Binance market data
- Grid trading strategy implementation
- Rate limiting for Binance API compliance
- Encrypted storage for API credentials using Cloak
- Risk management system with position sizing
- PubSub for real-time updates across the system

### Database Schema
- Users table with authentication
- API credentials with encryption
- Orders tracking with exchange integration
- Trades with TimescaleDB hypertable optimization
- Balances snapshot system
- Settings per user

### Trading Features
- Naive strategy (buy low, sell high)
- Grid strategy (automated grid trading)
- GenServer architecture (one per trading account)
- Order manager for centralized order tracking
- Risk manager with position limits
- Real-time market data via WebSocket

### UI Features
- Dashboard with market overview
- Trading page with active positions
- Portfolio management
- Settings configuration
- Real-time price updates via LiveView

## [0.1.0] - 2025-01-07

### Added
- Initial project setup with documentation
- Docker Compose configuration
- Environment configuration templates
- Makefile for common tasks
- Comprehensive documentation (README, IMPLEMENTATION_PLAN, QUICKSTART, etc.)

