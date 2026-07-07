# Exchange Adapter Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce an `ExchangeClient` behaviour so `DataCollector.BinanceClient` becomes "adapter #1" instead of being hardcoded everywhere, fix the DB-level `orders` uniqueness bug that would otherwise corrupt data the moment a second exchange exists, and make `TradingEngine.Trader`/`OrderManager`/`Credentials.test_credential` dispatch through the new abstraction. This does **not** add a second exchange yet — it produces working, testable software that behaves identically to today (100% Binance), but with the seam a Kraken adapter can plug into.

**Architecture:** A `@behaviour` (`create_order/3`, `cancel_order/4`, `get_open_orders/3`, `get_account/2`, `get_exchange_info/1`) that `BinanceClient` implements with zero changes to its function bodies (its signatures already match). A new `DataCollector.ExchangeRegistry.client_for/1` maps the `exchange` string on an `ApiCredential` to the adapter module. `api_credentials` gets a new `exchange` column (default `"binance"`). `orders`' uniqueness moves from global `order_id` to `(account_id, order_id)` — fixing a latent bug where two different accounts could never share an `order_id`, which will definitely happen once a second exchange exists.

**Tech Stack:** Elixir/Phoenix umbrella, Ecto/PostgreSQL, ExUnit + `Ecto.Adapters.SQL.Sandbox` (manual mode, already configured in `apps/shared_data/test/test_helper.exs`).

**Explicitly out of scope for this plan (see notes at the end):** `dashboard_web` LiveViews (`orders_live.ex`, `history_live.ex`, `portfolio_live.ex`, `trading_live.ex` — 20+ direct `BinanceClient` calls), `TradingEngine.SymbolInfo` (not exchange-aware, single caller in `conditional_chain.ex`), the canonical market-data/execution-report struct, and any actual second-exchange adapter (Kraken). These require either a live second exchange to test against or overlap with the separate strategy-payload-normalization work, and are scoped into follow-on plans.

---

### Task 1: `ExchangeClient` behaviour

**Files:**
- Create: `apps/data_collector/lib/data_collector/exchange_client.ex`

- [ ] **Step 1: Write the behaviour module**

```elixir
defmodule DataCollector.ExchangeClient do
  @moduledoc """
  Behaviour implemented by every exchange REST adapter (Binance, and future
  adapters like Kraken). Callers resolve the adapter module via
  `DataCollector.ExchangeRegistry.client_for/1` instead of calling an adapter
  module by name directly.

  Callback signatures mirror `DataCollector.BinanceClient`'s existing public
  API exactly, so it can implement this behaviour with no changes to its
  function bodies.
  """

  alias SharedData.Types

  @callback get_account(Types.api_key(), Types.secret_key()) :: Types.result(map())

  @callback create_order(Types.api_key(), Types.secret_key(), Types.order_params()) ::
              Types.result(Types.order())

  @callback cancel_order(Types.api_key(), Types.secret_key(), Types.symbol(), Types.order_id()) ::
              Types.result(map())

  @callback get_open_orders(Types.api_key(), Types.secret_key(), Types.symbol() | nil) ::
              Types.result([map()])

  @callback get_exchange_info(Types.symbol()) :: Types.result(map())
end
```

- [ ] **Step 2: Compile and confirm no errors**

Run: `mix compile`
Expected: compiles cleanly (a behaviour with only `@callback`s and no implementations yet has nothing to violate).

- [ ] **Step 3: Commit**

```bash
git add apps/data_collector/lib/data_collector/exchange_client.ex
git commit -m "feat(data_collector): add ExchangeClient behaviour"
```

---

### Task 2: `BinanceClient` implements `ExchangeClient`

**Files:**
- Modify: `apps/data_collector/lib/data_collector/binance_client.ex:1-16`

- [ ] **Step 1: Add the `@behaviour` declaration**

In `apps/data_collector/lib/data_collector/binance_client.ex`, change:

```elixir
defmodule DataCollector.BinanceClient do
  @moduledoc """
  HTTP client for Binance REST API with rate limiting and signature generation.
  ...
  """
  require Logger

  alias SharedData.Types
```

to:

```elixir
defmodule DataCollector.BinanceClient do
  @moduledoc """
  HTTP client for Binance REST API with rate limiting and signature generation.
  ...
  """
  @behaviour DataCollector.ExchangeClient

  require Logger

  alias SharedData.Types
```

(Leave the rest of the file — `get_account/2`, `create_order/3`, `cancel_order/4`, `get_open_orders/3`, `get_exchange_info/1`, and every other function — untouched. Their signatures already match the behaviour.)

- [ ] **Step 2: Compile with warnings surfaced**

Run: `mix compile --force --warnings-as-errors`
Expected: compiles cleanly with **zero** "function X required by behaviour ExchangeClient is not implemented" warnings. If any callback mismatches (e.g. an arity typo from Task 1), fix the `@callback` in `exchange_client.ex` to match `BinanceClient`'s real signature — `BinanceClient` is the source of truth here, not the other way around.

- [ ] **Step 3: Run existing Binance client tests to confirm no regression**

Run: `mix test apps/data_collector/test/binance_client_test.exs`
Expected: all existing tests still PASS (this change adds an annotation only, no behavior change).

- [ ] **Step 4: Commit**

```bash
git add apps/data_collector/lib/data_collector/binance_client.ex
git commit -m "feat(data_collector): BinanceClient implements ExchangeClient"
```

---

### Task 3: `ExchangeRegistry`

**Files:**
- Create: `apps/data_collector/lib/data_collector/exchange_registry.ex`
- Test: `apps/data_collector/test/exchange_registry_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule DataCollector.ExchangeRegistryTest do
  use ExUnit.Case, async: true

  alias DataCollector.ExchangeRegistry

  describe "client_for/1" do
    test "resolves \"binance\" to DataCollector.BinanceClient" do
      assert {:ok, DataCollector.BinanceClient} = ExchangeRegistry.client_for("binance")
    end

    test "returns an error for an unsupported exchange" do
      assert {:error, {:unsupported_exchange, "kraken"}} =
               ExchangeRegistry.client_for("kraken")
    end

    test "returns an error for garbage input" do
      assert {:error, {:unsupported_exchange, "not_a_real_exchange"}} =
               ExchangeRegistry.client_for("not_a_real_exchange")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/data_collector/test/exchange_registry_test.exs`
Expected: FAIL with "module DataCollector.ExchangeRegistry is not available" (or similar `UndefinedFunctionError`).

- [ ] **Step 3: Write the implementation**

```elixir
defmodule DataCollector.ExchangeRegistry do
  @moduledoc """
  Resolves an `exchange` string (as stored on `SharedData.Schemas.ApiCredential`)
  to the adapter module implementing `DataCollector.ExchangeClient` for it.

  Deliberately does not convert the input to an atom (it comes from the
  database/user input) — pattern-matches known string values instead so an
  unrecognized value can never create a new atom.
  """

  @spec client_for(String.t()) ::
          {:ok, module()} | {:error, {:unsupported_exchange, String.t()}}
  def client_for("binance"), do: {:ok, DataCollector.BinanceClient}
  def client_for(other), do: {:error, {:unsupported_exchange, other}}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/data_collector/test/exchange_registry_test.exs`
Expected: PASS (3 tests, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add apps/data_collector/lib/data_collector/exchange_registry.ex apps/data_collector/test/exchange_registry_test.exs
git commit -m "feat(data_collector): add ExchangeRegistry to resolve exchange -> adapter module"
```

---

### Task 4: `exchange` column on `api_credentials`

**Files:**
- Create: `apps/shared_data/priv/repo/migrations/20260705120000_add_exchange_to_api_credentials.exs`
- Modify: `apps/shared_data/lib/shared_data/schemas/api_credential.ex`
- Test: `apps/shared_data/test/schemas/api_credential_test.exs`

- [ ] **Step 1: Write the migration**

```elixir
defmodule SharedData.Repo.Migrations.AddExchangeToApiCredentials do
  use Ecto.Migration

  def change do
    alter table(:api_credentials) do
      add :exchange, :string, default: "binance", null: false
    end
  end
end
```

Save the file above directly under `apps/shared_data/priv/repo/migrations/` — the timestamp prefix and module name follow the same convention as the existing `20251125193710_add_is_testnet_to_api_credentials.exs` migration, so `mix ecto.gen.migration` isn't needed to scaffold it.

- [ ] **Step 2: Run the migration**

Run: `MIX_ENV=test mix ecto.migrate` (and `mix ecto.migrate` for dev, per this repo's `make db-migrate`)
Expected: `== Running ... AddExchangeToApiCredentials.change/0 forward` then `:ok`, no errors. Existing rows get `exchange = "binance"` from the column default.

- [ ] **Step 3: Write the failing test for the schema/changeset**

```elixir
defmodule SharedData.Schemas.ApiCredentialTest do
  use ExUnit.Case, async: true

  alias SharedData.Schemas.ApiCredential

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SharedData.Repo)
  end

  describe "exchange field" do
    test "defaults to \"binance\" when not provided" do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          label: "Main account"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :exchange) == "binance"
    end

    test "accepts an explicit supported exchange" do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          label: "Main account",
          exchange: "binance"
        })

      assert changeset.valid?
    end

    test "rejects an unsupported exchange" do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          label: "Main account",
          exchange: "kraken"
        })

      refute changeset.valid?
      assert %{exchange: ["unsupported exchange"]} = errors_on(changeset)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `mix test apps/shared_data/test/schemas/api_credential_test.exs`
Expected: FAIL — `Ecto.Changeset.get_field(changeset, :exchange) == "binance"` fails because the schema doesn't have the field yet (or returns `nil`), and the third test fails because there's no `validate_inclusion` yet to reject `"kraken"`.

- [ ] **Step 5: Update the schema**

In `apps/shared_data/lib/shared_data/schemas/api_credential.ex`, change:

```elixir
  schema "api_credentials" do
    field :api_key, SharedData.Encrypted.Binary
    field :secret_key, SharedData.Encrypted.Binary
    field :label, :string
    field :is_active, :boolean, default: true
    field :is_testnet, :boolean, default: false

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @doc false
  def changeset(api_credential, attrs) do
    api_credential
    |> cast(attrs, [:api_key, :secret_key, :label, :is_active, :is_testnet, :user_id])
    |> validate_required([:api_key, :secret_key, :label])
    |> validate_length(:label, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
    |> ensure_only_one_active()
  end
```

to:

```elixir
  schema "api_credentials" do
    field :api_key, SharedData.Encrypted.Binary
    field :secret_key, SharedData.Encrypted.Binary
    field :label, :string
    field :is_active, :boolean, default: true
    field :is_testnet, :boolean, default: false
    field :exchange, :string, default: "binance"

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @supported_exchanges ["binance"]

  @doc false
  def changeset(api_credential, attrs) do
    api_credential
    |> cast(attrs, [
      :api_key,
      :secret_key,
      :label,
      :is_active,
      :is_testnet,
      :exchange,
      :user_id
    ])
    |> validate_required([:api_key, :secret_key, :label])
    |> validate_length(:label, min: 1, max: 255)
    |> validate_inclusion(:exchange, @supported_exchanges, message: "unsupported exchange")
    |> foreign_key_constraint(:user_id)
    |> ensure_only_one_active()
  end
```

(`@supported_exchanges` is a plain module attribute list — extend it in each future adapter's plan, e.g. add `"kraken"` when the Kraken adapter plan lands.)

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test apps/shared_data/test/schemas/api_credential_test.exs`
Expected: PASS (3 tests, 0 failures).

- [ ] **Step 7: Run the full shared_data test suite to check for regressions**

Run: `mix test apps/shared_data/test`
Expected: all PASS, including the pre-existing `encrypted_binary_test.exs`.

- [ ] **Step 8: Commit**

```bash
git add apps/shared_data/priv/repo/migrations/20260705120000_add_exchange_to_api_credentials.exs apps/shared_data/lib/shared_data/schemas/api_credential.ex apps/shared_data/test/schemas/api_credential_test.exs
git commit -m "feat(shared_data): add exchange field to api_credentials"
```

---

### Task 5: Fix `orders` uniqueness to `(account_id, order_id)`

**Files:**
- Create: `apps/shared_data/priv/repo/migrations/20260705120100_fix_orders_order_id_uniqueness.exs`
- Modify: `apps/shared_data/lib/shared_data/schemas/order.ex:60`
- Test: `apps/shared_data/test/schemas/order_test.exs`

- [ ] **Step 1: Write the migration**

```elixir
defmodule SharedData.Repo.Migrations.FixOrdersOrderIdUniqueness do
  use Ecto.Migration

  def change do
    drop unique_index(:orders, [:order_id])

    create unique_index(:orders, [:account_id, :order_id],
             name: :orders_account_id_order_id_index
           )
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `MIX_ENV=test mix ecto.migrate`
Expected: drops the old global unique index and creates the new composite one. If this fails with a uniqueness violation, it means two existing rows already share an `order_id` across different accounts — stop and investigate the data before proceeding (do not silently force it through).

- [ ] **Step 3: Write the failing test**

```elixir
defmodule SharedData.Schemas.OrderTest do
  use ExUnit.Case, async: true

  alias SharedData.Repo
  alias SharedData.Schemas.{Order, Account, ApiCredential, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: "trader@example.com",
        password: "supersecret1",
        password_confirmation: "supersecret1"
      })
      |> Repo.insert()

    {:ok, credential_a} =
      %ApiCredential{}
      |> ApiCredential.changeset(%{
        api_key: "key-a",
        secret_key: "secret-a",
        label: "Account A",
        user_id: user.id
      })
      |> Repo.insert()

    {:ok, credential_b} =
      %ApiCredential{}
      |> ApiCredential.changeset(%{
        api_key: "key-b",
        secret_key: "secret-b",
        label: "Account B",
        user_id: user.id
      })
      |> Repo.insert()

    {:ok, account_a} =
      %Account{}
      |> Account.changeset(%{label: "Account A", user_id: user.id, api_credential_id: credential_a.id})
      |> Repo.insert()

    {:ok, account_b} =
      %Account{}
      |> Account.changeset(%{label: "Account B", user_id: user.id, api_credential_id: credential_b.id})
      |> Repo.insert()

    %{account_a: account_a, account_b: account_b}
  end

  test "the same order_id is allowed across two different accounts", %{
    account_a: account_a,
    account_b: account_b
  } do
    assert {:ok, _} =
             %Order{}
             |> Order.changeset(%{
               order_id: "12345",
               symbol: "BTCUSDT",
               type: "MARKET",
               side: "BUY",
               quantity: Decimal.new("0.001"),
               account_id: account_a.id
             })
             |> Repo.insert()

    assert {:ok, _} =
             %Order{}
             |> Order.changeset(%{
               order_id: "12345",
               symbol: "BTCUSDT",
               type: "MARKET",
               side: "BUY",
               quantity: Decimal.new("0.001"),
               account_id: account_b.id
             })
             |> Repo.insert()
  end

  test "the same order_id is rejected twice within the same account", %{account_a: account_a} do
    assert {:ok, _} =
             %Order{}
             |> Order.changeset(%{
               order_id: "99999",
               symbol: "BTCUSDT",
               type: "MARKET",
               side: "BUY",
               quantity: Decimal.new("0.001"),
               account_id: account_a.id
             })
             |> Repo.insert()

    assert {:error, changeset} =
             %Order{}
             |> Order.changeset(%{
               order_id: "99999",
               symbol: "BTCUSDT",
               type: "MARKET",
               side: "BUY",
               quantity: Decimal.new("0.001"),
               account_id: account_a.id
             })
             |> Repo.insert()

    assert %{order_id: ["has already been taken"]} =
             Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
```

- [ ] **Step 4: Run test to verify the first assertion fails**

Run: `mix test apps/shared_data/test/schemas/order_test.exs`
Expected: FAIL on "the same order_id is allowed across two different accounts" — the old global unique index (if migration from Step 2 hadn't run yet) or the changeset's `unique_constraint(:order_id)` (targeting the old index name) would still reject the second insert. If Step 2 already ran, this failure instead comes from the changeset not knowing the new constraint name yet (next step).

- [ ] **Step 5: Update the schema changeset**

In `apps/shared_data/lib/shared_data/schemas/order.ex`, change:

```elixir
    |> unique_constraint(:order_id)
    |> foreign_key_constraint(:account_id)
```

to:

```elixir
    |> unique_constraint([:account_id, :order_id], name: :orders_account_id_order_id_index)
    |> foreign_key_constraint(:account_id)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test apps/shared_data/test/schemas/order_test.exs`
Expected: PASS (2 tests, 0 failures).

- [ ] **Step 7: Run the full shared_data test suite**

Run: `mix test apps/shared_data/test`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add apps/shared_data/priv/repo/migrations/20260705120100_fix_orders_order_id_uniqueness.exs apps/shared_data/lib/shared_data/schemas/order.ex apps/shared_data/test/schemas/order_test.exs
git commit -m "fix(shared_data): scope orders uniqueness to (account_id, order_id)"
```

---

### Task 6: Rewire `Credentials.test_credential/1`

**Files:**
- Modify: `apps/shared_data/lib/shared_data/credentials.ex:272-276`

- [ ] **Step 1: Update `test_credential/1` to dispatch through the registry**

Change:

```elixir
  def test_credential(%ApiCredential{} = credential) do
    # Use runtime module lookup to avoid compile-time dependency on DataCollector
    # SharedData compiles before DataCollector, so we use apply/3
    apply(DataCollector.BinanceClient, :get_account, [credential.api_key, credential.secret_key])
  end
```

to:

```elixir
  def test_credential(%ApiCredential{} = credential) do
    # Use runtime module lookup to avoid compile-time dependency on DataCollector
    # SharedData compiles before DataCollector, so we use apply/3
    case apply(DataCollector.ExchangeRegistry, :client_for, [credential.exchange]) do
      {:ok, client_module} ->
        apply(client_module, :get_account, [credential.api_key, credential.secret_key])

      {:error, _reason} = error ->
        error
    end
  end
```

- [ ] **Step 2: Manually verify via IEx**

This function isn't covered by an existing test file and calls a real HTTP endpoint, so it isn't a good TDD candidate on its own — verify by hand instead.

Run: `iex -S mix` from the umbrella root, then:

```elixir
alias SharedData.Credentials
cred = %SharedData.Schemas.ApiCredential{
  api_key: System.get_env("BINANCE_API_KEY"),
  secret_key: System.get_env("BINANCE_SECRET_KEY"),
  exchange: "binance"
}
Credentials.test_credential(cred)
```

Expected: `{:ok, %{"balances" => [...], ...}}` against the configured testnet — same result as before this change (dispatch is transparent for `exchange: "binance"`).

- [ ] **Step 3: Commit**

```bash
git add apps/shared_data/lib/shared_data/credentials.ex
git commit -m "feat(shared_data): dispatch test_credential through ExchangeRegistry"
```

---

### Task 7: Rewire `TradingEngine.OrderManager`

**Files:**
- Modify: `apps/trading_engine/lib/trading_engine/order_manager.ex`

- [ ] **Step 1: Update `create_order/4` and `cancel_order/5` to take and dispatch by exchange**

Change:

```elixir
defmodule TradingEngine.OrderManager do
  @moduledoc """
  Manages order lifecycle and synchronization with Binance.
  """
  require Logger

  alias DataCollector.BinanceClient
  alias SharedData.Repo
  alias SharedData.Schemas.Order

  def create_order(account_id, api_key, secret_key, order_params) do
    # Create order on Binance
    case BinanceClient.create_order(api_key, secret_key, order_params) do
```

to:

```elixir
defmodule TradingEngine.OrderManager do
  @moduledoc """
  Manages order lifecycle and synchronization with the account's exchange.
  """
  require Logger

  alias DataCollector.ExchangeRegistry
  alias SharedData.Repo
  alias SharedData.Schemas.Order

  def create_order(account_id, exchange, api_key, secret_key, order_params) do
    with {:ok, client} <- ExchangeRegistry.client_for(exchange) do
      dispatch_create_order(client, account_id, api_key, secret_key, order_params)
    end
  end

  defp dispatch_create_order(client, account_id, api_key, secret_key, order_params) do
    # Create order on the account's exchange
    case client.create_order(api_key, secret_key, order_params) do
```

Then close out the new private function — the rest of the existing `case` body (the `{:ok, binance_order} -> ... error -> error` clauses) stays exactly as-is, just now inside `dispatch_create_order/5` instead of `create_order/4`. Similarly change:

```elixir
  def cancel_order(account_id, api_key, secret_key, symbol, order_id) do
    case BinanceClient.cancel_order(api_key, secret_key, symbol, order_id) do
```

to:

```elixir
  def cancel_order(account_id, exchange, api_key, secret_key, symbol, order_id) do
    with {:ok, client} <- ExchangeRegistry.client_for(exchange) do
      dispatch_cancel_order(client, account_id, api_key, secret_key, symbol, order_id)
    end
  end

  defp dispatch_cancel_order(client, account_id, api_key, secret_key, symbol, order_id) do
    case client.cancel_order(api_key, secret_key, symbol, order_id) do
```

(again, the rest of the existing body of each function is unchanged — only the head and the module call target change). `update_order_from_execution/1` is untouched — it only parses a raw execution report already in hand, no exchange dispatch involved (that raw-key parsing is exactly the "canonical struct" work scoped to the follow-on plan).

- [ ] **Step 2: Update the one caller in `trading_engine`**

`grep -rn "OrderManager.create_order\|OrderManager.cancel_order" apps/trading_engine apps/dashboard_web` shows `OrderManager` is not currently called from `Trader` itself — `Trader` calls `BinanceClient` directly (handled in Task 9). Confirm there are no other callers before proceeding:

Run: `grep -rn "OrderManager\.\(create_order\|cancel_order\)" apps/`
Expected: no results outside `order_manager.ex` itself yet. If this plan is executed against a codebase where a caller was added since this plan was written, update that call site's arity to match (insert the account's `exchange` as the second argument) before moving on — do not leave a caller on the old arity.

- [ ] **Step 3: Compile to confirm no broken callers**

Run: `mix compile --warnings-as-errors`
Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add apps/trading_engine/lib/trading_engine/order_manager.ex
git commit -m "feat(trading_engine): OrderManager dispatches via ExchangeRegistry"
```

---

### Task 8: Thread `exchange` through `StrategyManager`

**Files:**
- Modify: `apps/trading_engine/lib/trading_engine/strategy_manager.ex:319-328`

- [ ] **Step 1: Pass the account's exchange into the Trader opts**

Change:

```elixir
            opts = [
              setting_id: setting.id,
              account_id: account.id,
              api_key: account.api_credential.api_key,
              secret_key: account.api_credential.secret_key,
              strategy: strategy_module,
              strategy_config: config
            ]

            AccountSupervisor.start_trader(account.id, opts)
```

to:

```elixir
            opts = [
              setting_id: setting.id,
              account_id: account.id,
              exchange: account.api_credential.exchange,
              api_key: account.api_credential.api_key,
              secret_key: account.api_credential.secret_key,
              strategy: strategy_module,
              strategy_config: config
            ]

            AccountSupervisor.start_trader(account.id, opts)
```

- [ ] **Step 2: Confirm `Settings.get_setting_with_credentials/1` preloads `api_credential`**

Run: `grep -n "get_setting_with_credentials" apps/shared_data/lib/shared_data/settings.ex`
Expected: the preload chain already includes `account: :api_credential` (it must, since `account.api_credential.api_key` on the line above already works today) — confirm the same preload also brings back the new `exchange` field, which it will automatically since it's a plain column on the same already-preloaded schema, not a new association.

- [ ] **Step 3: Compile**

Run: `mix compile --warnings-as-errors`
Expected: clean compile (this task only adds a key to a keyword list; `Trader.init/1` reading it is Task 9).

- [ ] **Step 4: Commit**

```bash
git add apps/trading_engine/lib/trading_engine/strategy_manager.ex
git commit -m "feat(trading_engine): pass account exchange into Trader opts"
```

---

### Task 9: Rewire `TradingEngine.Trader`

**Files:**
- Modify: `apps/trading_engine/lib/trading_engine/trader.ex:11,38-135,160,378-406,525-604`

This is the largest task — `Trader` calls `BinanceClient` directly in 5 places, 3 of them nested inside private recovery-check helper functions that need `exchange` threaded through their arguments as well as `init/1`'s.

- [ ] **Step 1: Add `exchange` to init and state**

Change:

```elixir
  alias DataCollector.BinanceClient
  alias TradingEngine.{RiskManager, Strategy}
  alias SharedData.{Config, Types}
```

to:

```elixir
  alias DataCollector.ExchangeRegistry
  alias TradingEngine.{RiskManager, Strategy}
  alias SharedData.{Config, Types}
```

Change:

```elixir
  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    setting_id = Keyword.fetch!(opts, :setting_id)
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    strategy = Keyword.fetch!(opts, :strategy)
    strategy_config = Keyword.fetch!(opts, :strategy_config)
```

to:

```elixir
  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    setting_id = Keyword.fetch!(opts, :setting_id)
    exchange = Keyword.fetch!(opts, :exchange)
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    strategy = Keyword.fetch!(opts, :strategy)
    strategy_config = Keyword.fetch!(opts, :strategy_config)
```

Change the recovery call:

```elixir
    recovery_info = check_for_recovery(setting_id, api_key, secret_key, symbols)
```

to:

```elixir
    recovery_info = check_for_recovery(setting_id, exchange, api_key, secret_key, symbols)
```

Change the state map:

```elixir
    state = %{
      account_id: account_id,
      setting_id: setting_id,
      api_key: api_key,
      secret_key: secret_key,
```

to:

```elixir
    state = %{
      account_id: account_id,
      setting_id: setting_id,
      exchange: exchange,
      api_key: api_key,
      secret_key: secret_key,
```

- [ ] **Step 2: Add an internal dispatch helper**

Add this private function anywhere in the private-functions section of `trader.ex` (e.g. right after `via_tuple/1`):

```elixir
  # Resolves state.exchange to its adapter module. Raises on an unsupported
  # exchange rather than returning an error tuple: by the time a Trader is
  # running, its account's exchange has already passed ApiCredential's
  # validate_inclusion, so this can only fail from stale/corrupt state, which
  # should crash the Trader loudly rather than silently no-op an order call.
  @spec exchange_client!(map()) :: module()
  defp exchange_client!(state) do
    case ExchangeRegistry.client_for(state.exchange) do
      {:ok, client} -> client
      {:error, reason} -> raise "Trader for account #{state.account_id}: #{inspect(reason)}"
    end
  end
```

- [ ] **Step 3: Rewire the `place_order` call site (line 160)**

Change:

```elixir
        case BinanceClient.create_order(state.api_key, state.secret_key, order_params) do
```

to:

```elixir
        case exchange_client!(state).create_order(state.api_key, state.secret_key, order_params) do
```

- [ ] **Step 4: Rewire `cancel_open_orders_on_stop/2` (lines 378-406)**

Change:

```elixir
  defp cancel_open_orders_on_stop(state, attempts_left) do
    case BinanceClient.get_open_orders(state.api_key, state.secret_key, state.symbol) do
      {:ok, []} ->
        Logger.info("Grid cleanup: no open orders remain for #{state.symbol}")
        :ok

      {:ok, orders} ->
        Logger.info(
          "Grid cleanup: cancelling #{length(orders)} open order(s) for #{state.symbol}"
        )

        Enum.each(orders, fn order ->
          case BinanceClient.cancel_order(
                 state.api_key,
                 state.secret_key,
                 state.symbol,
                 order["orderId"]
               ) do
```

to:

```elixir
  defp cancel_open_orders_on_stop(state, attempts_left) do
    client = exchange_client!(state)

    case client.get_open_orders(state.api_key, state.secret_key, state.symbol) do
      {:ok, []} ->
        Logger.info("Grid cleanup: no open orders remain for #{state.symbol}")
        :ok

      {:ok, orders} ->
        Logger.info(
          "Grid cleanup: cancelling #{length(orders)} open order(s) for #{state.symbol}"
        )

        Enum.each(orders, fn order ->
          case client.cancel_order(
                 state.api_key,
                 state.secret_key,
                 state.symbol,
                 order["orderId"]
               ) do
```

- [ ] **Step 5: Thread `exchange` through the recovery-check helper chain (lines 525-604)**

Change:

```elixir
  defp check_for_recovery(setting_id, api_key, secret_key, symbols) when is_list(symbols) do
    # 1. Check for existing chain state in DB
    case SharedData.ChainStates.get_chain_state_by_setting(setting_id) do
      nil ->
        # No existing state, check for orphaned open orders across all symbols
        check_orphaned_orders(api_key, secret_key, symbols)

      %{current_state: state} when state in ["completed", "error"] ->
        # Chain completed or errored, no recovery needed
        nil

      %{current_state: "stopped"} = chain_state ->
        # Chain was stopped cleanly - can recover if setting is active
        Logger.info("Found stopped chain state for setting #{setting_id}, allowing recovery")
        verify_and_build_recovery(chain_state, api_key, secret_key, symbols)

      chain_state ->
        # Active chain state found - check if pending order still exists
        # Use all symbols for comprehensive order checking
        verify_and_build_recovery(chain_state, api_key, secret_key, symbols)
    end
  end

  # Fallback for single symbol (backwards compatibility)
  defp check_for_recovery(setting_id, api_key, secret_key, symbol) when is_binary(symbol) do
    check_for_recovery(setting_id, api_key, secret_key, [symbol])
  end

  # Check all symbols for orphaned orders
  defp check_orphaned_orders(api_key, secret_key, symbols) when is_list(symbols) do
    all_orders =
      symbols
      |> Enum.flat_map(fn symbol ->
        case BinanceClient.get_open_orders(api_key, secret_key, symbol) do
          {:ok, orders} -> orders
          {:error, _} -> []
        end
      end)
```

to:

```elixir
  defp check_for_recovery(setting_id, exchange, api_key, secret_key, symbols)
       when is_list(symbols) do
    # 1. Check for existing chain state in DB
    case SharedData.ChainStates.get_chain_state_by_setting(setting_id) do
      nil ->
        # No existing state, check for orphaned open orders across all symbols
        check_orphaned_orders(exchange, api_key, secret_key, symbols)

      %{current_state: state} when state in ["completed", "error"] ->
        # Chain completed or errored, no recovery needed
        nil

      %{current_state: "stopped"} = chain_state ->
        # Chain was stopped cleanly - can recover if setting is active
        Logger.info("Found stopped chain state for setting #{setting_id}, allowing recovery")
        verify_and_build_recovery(chain_state, exchange, api_key, secret_key, symbols)

      chain_state ->
        # Active chain state found - check if pending order still exists
        # Use all symbols for comprehensive order checking
        verify_and_build_recovery(chain_state, exchange, api_key, secret_key, symbols)
    end
  end

  # Fallback for single symbol (backwards compatibility)
  defp check_for_recovery(setting_id, exchange, api_key, secret_key, symbol)
       when is_binary(symbol) do
    check_for_recovery(setting_id, exchange, api_key, secret_key, [symbol])
  end

  # Check all symbols for orphaned orders
  defp check_orphaned_orders(exchange, api_key, secret_key, symbols) when is_list(symbols) do
    {:ok, client} = ExchangeRegistry.client_for(exchange)

    all_orders =
      symbols
      |> Enum.flat_map(fn symbol ->
        case client.get_open_orders(api_key, secret_key, symbol) do
          {:ok, orders} -> orders
          {:error, _} -> []
        end
      end)
```

Change:

```elixir
  defp verify_and_build_recovery(chain_state, api_key, secret_key, symbols)
       when is_list(symbols) do
    pending_order_id = chain_state.pending_order_id

    # Check all symbols for open orders (pending order might be on any symbol)
    all_open_orders =
      symbols
      |> Enum.flat_map(fn symbol ->
        case BinanceClient.get_open_orders(api_key, secret_key, symbol) do
          {:ok, orders} -> orders
          {:error, _} -> []
        end
      end)
```

to:

```elixir
  defp verify_and_build_recovery(chain_state, exchange, api_key, secret_key, symbols)
       when is_list(symbols) do
    pending_order_id = chain_state.pending_order_id
    {:ok, client} = ExchangeRegistry.client_for(exchange)

    # Check all symbols for open orders (pending order might be on any symbol)
    all_open_orders =
      symbols
      |> Enum.flat_map(fn symbol ->
        case client.get_open_orders(api_key, secret_key, symbol) do
          {:ok, orders} -> orders
          {:error, _} -> []
        end
      end)
```

- [ ] **Step 6: Grep for any other callers of the now-changed private-function arities**

Run: `grep -n "check_for_recovery(\|check_orphaned_orders(\|verify_and_build_recovery(" apps/trading_engine/lib/trading_engine/trader.ex`
Expected: every call site shown now passes `exchange` in the new position (the ones fixed above) — if any call site is not yet updated, apply the same argument insertion before moving on. (These are private functions, so no cross-module callers to check.)

- [ ] **Step 7: Compile**

Run: `mix compile --warnings-as-errors`
Expected: clean compile. `alias DataCollector.BinanceClient` was removed in Step 1 — if compilation reports an unused-alias warning for anything, or a `BinanceClient` reference was missed in Steps 3-5, fix it now (search: `grep -n "BinanceClient" apps/trading_engine/lib/trading_engine/trader.ex` should return zero results).

- [ ] **Step 8: Run the existing trading_engine test suite**

Run: `mix test apps/trading_engine/test`
Expected: all PASS — `naive_test.exs`, `grid_test.exs`, `risk_manager_test.exs` don't exercise `Trader`'s GenServer directly (per current test coverage), so this mainly confirms nothing else in the app broke from the alias/compile changes.

- [ ] **Step 9: Manual smoke test against testnet**

`Trader` is a GenServer that places real (testnet) orders — there's no existing test harness for it, so verify by hand, matching this repo's existing testnet-based workflow:

Run: `make server-iex` (or `iex -S mix phx.server` per this repo's dev workflow), then from the running dashboard, start a Naive or Grid strategy on a test account exactly as you would today, and confirm:
- The Trader process starts without crashing (check logs for `Starting Trader for setting ...`).
- An order placed through the UI still succeeds against `https://testnet.binance.vision` (same as before this change).
- Stopping the strategy still cancels open orders cleanly (exercises `cancel_open_orders_on_stop/2`).

Expected: identical behavior to before this plan — this task is a pure refactor for `exchange: "binance"`, so anything different is a regression to fix before committing.

- [ ] **Step 10: Commit**

```bash
git add apps/trading_engine/lib/trading_engine/trader.ex
git commit -m "feat(trading_engine): Trader dispatches via ExchangeRegistry"
```

---

### Task 10: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: all tests across all 4 apps PASS, zero failures.

- [ ] **Step 2: Run credo and format check**

Run: `make check` (per this repo's `Makefile` — runs format + credo + tests)
Expected: no formatting diffs, no credo warnings introduced by this plan's changes.

- [ ] **Step 3: Confirm no remaining direct `BinanceClient` references in the files this plan touched**

Run: `grep -n "BinanceClient" apps/trading_engine/lib/trading_engine/trader.ex apps/trading_engine/lib/trading_engine/order_manager.ex apps/shared_data/lib/shared_data/credentials.ex`
Expected: **zero matches** — every one of these three files should now go through `ExchangeRegistry` instead of naming `BinanceClient` directly. (`apps/trading_engine/lib/trading_engine/symbol_info.ex` and every `dashboard_web` LiveView **still reference `BinanceClient` directly** — that's expected per this plan's explicit scope boundary, not a bug to fix here.)

- [ ] **Step 4: Final commit if any cleanup was needed**

If Steps 1-3 required fixes, commit them:

```bash
git add -A
git commit -m "chore: fix regressions found in exchange-adapter-foundation regression pass"
```

(Skip this step if Steps 1-3 passed clean with no changes needed.)

---

## Notes for whoever picks up the next plan

- **Config is still compile-time (`Application.compile_env(:binance, :end_point, ...)` in `binance_client.ex:16`, plus the `:binance` config key in `config/dev.exs`/`config/runtime.exs`).** This plan doesn't touch it — Binance's base URL never needs to change without a recompile today, so there's nothing broken yet. Moving to runtime, per-exchange config (`config :data_collector, exchanges: [binance: [...], kraken: [...]]`) only becomes necessary once a second adapter's base URL needs to be set independently — do it as the first step of the Kraken-adapter plan, alongside adding Kraken's own config.
- **`dashboard_web` still calls `BinanceClient` directly in ~20 places** across `orders_live.ex`, `history_live.ex`, `portfolio_live.ex`, `trading_live.ex`. Rewiring these to `ExchangeRegistry` only matters once a second exchange actually exists to route to — bundle it into the Kraken-adapter plan, and test it against Kraken's testnet, not just by inspection.
- **`TradingEngine.SymbolInfo`** caches precision by `symbol` alone (global ETS table, no exchange dimension) — its single caller is `conditional_chain.ex:767`, which is already in scope for the canonical-struct/strategy-migration plan. Make `SymbolInfo` exchange-aware (`{exchange, symbol}` cache key) as part of that plan, not this one.
- **Found and deliberately not fixed:** `apps/dashboard_web/lib/dashboard_web/live/chains_live.ex:864-867` calls `TradingEngine.AccountSupervisor.start_trader/2` with only `setting_id:` in `opts` — missing `account_id` handling aside, it's missing `api_key`/`secret_key`/`strategy`/`strategy_config`/(now)`exchange` entirely, which would crash `Trader.init/1`'s `Keyword.fetch!/2` calls. This looks like a pre-existing bug unrelated to multi-exchange support — flagging it here rather than fixing it silently as a drive-by change.
