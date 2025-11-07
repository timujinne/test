defmodule SharedData.Repo.Migrations.EnableTimescaledb do
  use Ecto.Migration

  def up do
    # Enable TimescaleDB extension if available
    # This is safe to run even if TimescaleDB is not installed
    execute("CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;")
  end

  def down do
    # Don't drop the extension on rollback as it might be used by other databases
    execute("SELECT 1;")
  end
end
