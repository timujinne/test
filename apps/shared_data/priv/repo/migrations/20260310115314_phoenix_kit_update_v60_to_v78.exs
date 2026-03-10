defmodule Ecto.Migrations.PhoenixKitUpdateV60ToV78 do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # PhoenixKit Update Migration: V60 -> V78
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 78,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V60
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 60
    )
  end
end
