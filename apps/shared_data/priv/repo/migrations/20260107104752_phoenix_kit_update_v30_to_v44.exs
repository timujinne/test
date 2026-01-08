defmodule Ecto.Migrations.PhoenixKitUpdateV30ToV44 do
  @moduledoc false
  use Ecto.Migration

  def up do
    # PhoenixKit Update Migration: V30 -> V44
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 44,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V30
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 30
    )
  end
end
