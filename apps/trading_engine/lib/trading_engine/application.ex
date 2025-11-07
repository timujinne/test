defmodule TradingEngine.Application do
  @moduledoc """
  The TradingEngine Application Service.

  This application manages trading strategies and order execution.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Dynamic supervisor for trader processes (one per account)
      {DynamicSupervisor, name: TradingEngine.AccountSupervisor, strategy: :one_for_one},
      # Order manager for tracking orders
      TradingEngine.OrderManager,
      # Risk manager for position sizing and risk control
      TradingEngine.RiskManager
    ]

    opts = [strategy: :one_for_one, name: TradingEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
