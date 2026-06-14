defmodule Ecto.Migrations.PhoenixKitUpdateV78ToV84 do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # PhoenixKit Update Migration: V78 -> V84
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 84,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V78
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 78
    )
  end
end
