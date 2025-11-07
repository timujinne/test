defmodule SharedData.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SharedData.Repo,
      SharedData.Vault
    ]

    opts = [strategy: :one_for_one, name: SharedData.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
