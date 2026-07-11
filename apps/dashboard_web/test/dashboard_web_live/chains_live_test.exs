defmodule DashboardWeb.ChainsLiveTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias SharedData.{Accounts, ChainStates, Settings}
  alias TradingEngine.StrategyManager

  # `start_chain`/`stop_chain`/`cancel_chain` now route through the
  # VM-wide singleton TradingEngine.StrategyManager, which — for a *fresh*
  # setting (no chain_state row yet) — synchronously spawns a real Trader
  # process whose init/1 does two DB reads from the Trader's *own* pid, not
  # this test's: (1) StrategyManager itself reading credentials, and (2) the
  # newly-spawned Trader checking for recovery state. We don't know the
  # Trader's pid ahead of time to `Sandbox.allow/3` it individually, so — as
  # recommended by Ecto's own Sandbox docs for exactly this "code under test
  # spawns processes I can't enumerate in advance" scenario — we put the
  # Sandbox in `{:shared, self()}` mode for the test's duration instead.
  # This is safe specifically because this module is `async: false`: ExUnit
  # only ever runs `async: false` modules strictly one at a time, after every
  # `async: true` module has already finished (ex_unit/lib/ex_unit/runner.ex
  # `async_loop/4`), so no other test can be touching the DB concurrently.
  setup do
    :ok = Sandbox.checkout(SharedData.Repo)
    Sandbox.mode(SharedData.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(SharedData.Repo, :manual) end)
    :ok
  end

  describe "start_chain / stop_chain / cancel_chain route through StrategyManager (10a)" do
    test "starting a chain no longer raises and registers a running trader with StrategyManager" do
      setting = chain_setting_fixture()
      socket = build_socket(account_id: setting.account_id)

      assert {:noreply, socket} =
               DashboardWeb.ChainsLive.handle_event(
                 "start_chain",
                 %{"id" => setting.id},
                 socket
               )

      refute Phoenix.Flash.get(socket.assigns.flash, :error)
      assert Phoenix.Flash.get(socket.assigns.flash, :info) =~ "started"

      assert StrategyManager.is_running?(setting.id)
      assert %{is_active: true} = Settings.get_setting(setting.id)

      on_exit(fn -> StrategyManager.stop_strategy(setting.id) end)
    end

    test "stopping a chain deactivates the setting and StrategyManager no longer reports it running" do
      setting = chain_setting_fixture()
      assert {:ok, _pid} = StrategyManager.start_strategy(setting.id)
      assert StrategyManager.is_running?(setting.id)

      chain_state = active_chain_state_fixture(setting)
      socket = build_socket(account_id: setting.account_id)

      assert {:noreply, socket} =
               DashboardWeb.ChainsLive.handle_event(
                 "stop_chain",
                 %{"id" => chain_state.id},
                 socket
               )

      refute Phoenix.Flash.get(socket.assigns.flash, :error)

      refute StrategyManager.is_running?(setting.id)
      assert %{is_active: false} = Settings.get_setting(setting.id)
    end

    test "cancelling a chain stops the trader and marks the chain state as error" do
      setting = chain_setting_fixture()
      assert {:ok, _pid} = StrategyManager.start_strategy(setting.id)
      assert StrategyManager.is_running?(setting.id)

      chain_state = active_chain_state_fixture(setting)
      socket = build_socket(account_id: setting.account_id)

      assert {:noreply, socket} =
               DashboardWeb.ChainsLive.handle_event(
                 "cancel_chain",
                 %{"id" => chain_state.id},
                 socket
               )

      refute Phoenix.Flash.get(socket.assigns.flash, :error)

      refute StrategyManager.is_running?(setting.id)
      assert %{current_state: "error"} = ChainStates.get_chain_state(chain_state.id)
    end
  end

  # -- fixtures --

  defp chain_setting_fixture do
    {:ok, user} =
      Accounts.create_user(%{
        email: "chains-#{System.unique_integer([:positive])}@example.com",
        password: "password1234",
        password_confirmation: "password1234"
      })

    {:ok, credential} =
      Accounts.create_api_credential(user.id, %{
        api_key: "test-key",
        secret_key: "test-secret",
        label: "Test credential",
        exchange: "binance"
      })

    # Deliberately point this credential at an exchange string
    # DataCollector.MarketStream doesn't recognize, so Trader.init/1's
    # ticker-subscribe step (which always runs — ConditionalChain.requirements/1
    # hardcodes ticks: true) hits MarketStream's existing, graceful
    # "unsupported exchange" error branch instead of opening a real
    # WebSocket connection to a live exchange. This bypasses
    # ApiCredential's normal changeset validation (which rightly only
    # allows real supported exchanges for actual UI/API use) via
    # Ecto.Changeset.change/2 — purely so this test can exercise a real,
    # complete Trader boot deterministically and without any network I/O,
    # per this repo's "unit tests use canned fixtures only" rule.
    credential =
      credential
      |> Ecto.Changeset.change(exchange: "test_no_network")
      |> SharedData.Repo.update!()

    {:ok, account} =
      Accounts.create_account(user.id, %{
        label: "Test account",
        api_credential_id: credential.id
      })

    {:ok, setting} =
      Settings.create_setting(%{
        account_id: account.id,
        strategy_name: "conditional_chain",
        config: %{"symbol" => "BTCUSDT", "steps" => []},
        is_active: false
      })

    # A pre-existing chain_state in a terminal state ("error") makes
    # Trader.init/1's recovery check (check_for_recovery/4) short-circuit to
    # `nil` directly, without ever calling the exchange client's
    # *authenticated* get_open_orders/2 — the other live-credentials network
    # call this codebase's Trader boot path makes (via check_orphaned_orders/3)
    # for any setting with no prior chain_state row at all. Without this seed
    # row, StrategyManager.start_strategy/1 on a brand-new setting would make
    # a real authenticated HTTP call, which this repo's rules forbid in tests.
    {:ok, _seed_chain_state} =
      ChainStates.create_chain_state(%{
        setting_id: setting.id,
        chain_id: "seed-#{setting.id}",
        current_state: "error"
      })

    setting
  end

  # The chain_state a running chain's stop/cancel actions target — distinct
  # from chain_setting_fixture/0's seed row (different chain_id), representing
  # the in-progress execution the UI is stopping/cancelling.
  defp active_chain_state_fixture(setting) do
    {:ok, chain_state} =
      ChainStates.create_chain_state(%{
        setting_id: setting.id,
        chain_id: "active-#{setting.id}",
        current_state: "awaiting_step"
      })

    chain_state
  end

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, Map.new(assigns))
    }
  end
end
