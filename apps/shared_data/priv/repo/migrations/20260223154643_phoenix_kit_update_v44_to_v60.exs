defmodule Ecto.Migrations.PhoenixKitUpdateV44ToV60 do
  @moduledoc false
  use Ecto.Migration

  def up do
    # PhoenixKit Update Migration: V44 -> V60
    PhoenixKit.Migrations.up(
      prefix: "public",
      version: 60,
      create_schema: false
    )
  end

  def down do
    # Rollback PhoenixKit to V44
    PhoenixKit.Migrations.down(
      prefix: "public",
      version: 44
    )
  end
end
