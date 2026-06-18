defmodule DashboardWeb.NavInit do
  @moduledoc """
  Registers the Trading/Automation sidebar groups into PhoenixKit's dashboard
  registry so the trading admin tabs render in the sidebar above PhoenixKit's
  built-in groups. PhoenixKit's public register_groups/1 OVERWRITES the group
  list and loads defaults asynchronously, so we wait for the defaults
  (:admin_main) then re-register current ++ ours (merge by id). Idempotent.
  """
  use GenServer
  require Logger

  alias PhoenixKit.Dashboard

  @trading_groups [
    %{id: :trading, label: "Trading", priority: 10},
    %{id: :trading_automation, label: "Automation", priority: 20}
  ]

  def start_link(_), do: GenServer.start_link(__MODULE__, %{tries: 0}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state, {:continue, :register}}

  @impl true
  def handle_continue(:register, state), do: do_register(state)

  @impl true
  def handle_info(:retry, state), do: do_register(state)

  defp do_register(state) do
    groups = Dashboard.get_groups()

    cond do
      Enum.any?(groups, &(&1.id == :trading)) ->
        {:noreply, state}

      Enum.any?(groups, &(&1.id == :admin_main)) ->
        missing = Enum.reject(@trading_groups, fn g -> Enum.any?(groups, &(&1.id == g.id)) end)
        if missing != [], do: Dashboard.register_groups(groups ++ missing)
        {:noreply, state}

      state.tries < 100 ->
        Process.send_after(self(), :retry, 100)
        {:noreply, %{state | tries: state.tries + 1}}

      true ->
        Logger.warning("[NavInit] PhoenixKit dashboard groups not loaded; trading nav groups skipped")
        {:noreply, state}
    end
  end
end
