defmodule SharedData.Repo.Migrations.EnableTimescaledb do
  use Ecto.Migration

  # TimescaleDB is optional - skip if not installed
  # This allows the project to work without TimescaleDB extension
  def up do
    # Skip TimescaleDB - use regular tables instead
    # If you have TimescaleDB installed, uncomment:
    # execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE"
    :ok
  end

  def down do
    :ok
  end
end
