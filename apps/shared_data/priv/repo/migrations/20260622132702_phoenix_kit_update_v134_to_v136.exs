defmodule Ecto.Migrations.PhoenixKitUpdateV134ToV136 do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # PhoenixKit Update Migration: V134 -> V136
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 136,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V134
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 134
    )
  end
end
