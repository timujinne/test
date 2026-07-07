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
