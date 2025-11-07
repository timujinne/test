defmodule SharedData.Application do
  @moduledoc """
  The SharedData Application Service.

  This application manages the database connection and shared data structures
  for the Binance Trading System.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      SharedData.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: SharedData.PubSub}
    ]

    opts = [strategy: :one_for_one, name: SharedData.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
