defmodule DashboardWeb.Forms.AccountFormTest do
  use ExUnit.Case, async: true

  alias DashboardWeb.Forms.AccountForm

  describe "changeset/2 exchange validation" do
    test "binance does not require a passphrase" do
      changeset =
        AccountForm.changeset(AccountForm.new(), %{
          "label" => "Main",
          "api_key" => "1234567890",
          "secret_key" => "1234567890",
          "exchange" => "binance"
        })

      assert changeset.valid?
    end

    test "okx requires a passphrase" do
      changeset =
        AccountForm.changeset(AccountForm.new(), %{
          "label" => "Main",
          "api_key" => "1234567890",
          "secret_key" => "1234567890",
          "exchange" => "okx"
        })

      refute changeset.valid?
      assert %{passphrase: ["can't be blank"]} = errors_on(changeset)
    end

    test "okx is valid when a passphrase is provided" do
      changeset =
        AccountForm.changeset(AccountForm.new(), %{
          "label" => "Main",
          "api_key" => "1234567890",
          "secret_key" => "1234567890",
          "passphrase" => "my-passphrase",
          "exchange" => "okx"
        })

      assert changeset.valid?
    end

    test "kraken does not require a passphrase" do
      changeset =
        AccountForm.changeset(AccountForm.new(), %{
          "label" => "Main",
          "api_key" => "1234567890",
          "secret_key" => "1234567890",
          "exchange" => "kraken"
        })

      assert changeset.valid?
    end
  end

  describe "changeset_for_edit/2" do
    test "passphrase is optional (empty means keep current)" do
      changeset =
        AccountForm.changeset_for_edit(AccountForm.new(), %{
          "label" => "Main"
        })

      assert changeset.valid?
    end

    test "passphrase can be updated together with api/secret keys" do
      changeset =
        AccountForm.changeset_for_edit(AccountForm.new(), %{
          "label" => "Main",
          "api_key" => "1234567890",
          "secret_key" => "1234567890",
          "passphrase" => "new-passphrase"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :passphrase) == "new-passphrase"
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
