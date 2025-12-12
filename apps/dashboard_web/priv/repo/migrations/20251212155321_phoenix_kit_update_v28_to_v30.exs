defmodule Ecto.Migrations.PhoenixKitUpdateV28ToV30 do
  @moduledoc false
  use Ecto.Migration

  def up do
    # PhoenixKit Update Migration: V28 -> V30
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 30,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V28
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 28
    )
  end
end
