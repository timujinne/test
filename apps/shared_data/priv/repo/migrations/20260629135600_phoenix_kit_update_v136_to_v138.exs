defmodule Ecto.Migrations.PhoenixKitUpdateV136ToV138 do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # PhoenixKit Update Migration: V136 -> V138
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 138,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V136
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 136
    )
  end
end
