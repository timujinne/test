defmodule Ecto.Migrations.PhoenixKitUpdateV84ToV134 do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # PhoenixKit Update Migration: V84 -> V134
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 134,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V84
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 84
    )
  end
end
