defmodule TradingEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: TradingEngine.TraderRegistry},
      {DynamicSupervisor, name: TradingEngine.AccountSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: TradingEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
