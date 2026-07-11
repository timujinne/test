defmodule SharedData.Schemas.ApiCredentialTest do
  use ExUnit.Case, async: true

  alias SharedData.Repo
  alias SharedData.Schemas.{ApiCredential, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SharedData.Repo)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: "okx-trader@example.com",
        password: "supersecret1",
        password_confirmation: "supersecret1"
      })
      |> Repo.insert()

    %{user: user}
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

    test "accepts \"okx\" as a supported exchange" do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          passphrase: "passphrase",
          label: "OKX account",
          exchange: "okx"
        })

      assert changeset.valid?
    end

    test "accepts \"kraken\" as a supported exchange without a passphrase" do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          label: "Kraken account",
          exchange: "kraken"
        })

      assert changeset.valid?
    end

    test "rejects an unsupported exchange" do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          label: "Main account",
          exchange: "coinbase"
        })

      refute changeset.valid?
      assert %{exchange: ["unsupported exchange"]} = errors_on(changeset)
    end
  end

  describe "passphrase field" do
    test "is accepted, persisted, and readable back decrypted", %{user: user} do
      {:ok, credential} =
        %ApiCredential{}
        |> ApiCredential.changeset(%{
          api_key: "okx-key",
          secret_key: "okx-secret",
          passphrase: "okx-passphrase",
          label: "Has a passphrase",
          user_id: user.id
        })
        |> Repo.insert()

      assert credential.passphrase == "okx-passphrase"

      reloaded = Repo.get!(ApiCredential, credential.id)
      assert reloaded.passphrase == "okx-passphrase"
    end

    test "is stored encrypted at rest (raw column differs from plaintext)", %{user: user} do
      {:ok, credential} =
        %ApiCredential{}
        |> ApiCredential.changeset(%{
          api_key: "okx-key",
          secret_key: "okx-secret",
          passphrase: "super-secret-passphrase",
          label: "Has a passphrase",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, %{rows: [[raw_passphrase]]}} =
        Repo.query("SELECT passphrase FROM api_credentials WHERE id = $1", [
          Ecto.UUID.dump!(credential.id)
        ])

      refute raw_passphrase == "super-secret-passphrase"
      refute is_nil(raw_passphrase)
    end

    test "is fine when absent (nil)", %{user: user} do
      changeset =
        ApiCredential.changeset(%ApiCredential{}, %{
          api_key: "key",
          secret_key: "secret",
          label: "Main account",
          user_id: user.id
        })

      assert changeset.valid?

      {:ok, credential} = Repo.insert(changeset)

      assert is_nil(credential.passphrase)

      reloaded = Repo.get!(ApiCredential, credential.id)
      assert is_nil(reloaded.passphrase)
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
