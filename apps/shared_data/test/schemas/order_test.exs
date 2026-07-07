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
      |> Account.changeset(%{
        label: "Account A",
        user_id: user.id,
        api_credential_id: credential_a.id
      })
      |> Repo.insert()

    {:ok, account_b} =
      %Account{}
      |> Account.changeset(%{
        label: "Account B",
        user_id: user.id,
        api_credential_id: credential_b.id
      })
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
