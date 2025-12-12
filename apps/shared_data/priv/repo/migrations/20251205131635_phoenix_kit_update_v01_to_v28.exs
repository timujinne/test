defmodule Ecto.Migrations.PhoenixKitUpdateV01ToV28 do
  @moduledoc false
  use Ecto.Migration

  def up do
    # PhoenixKit Update Migration: V01 -> V28
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 28,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V01
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 1
    )
  end
end
