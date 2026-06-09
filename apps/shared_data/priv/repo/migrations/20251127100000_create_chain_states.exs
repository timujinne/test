defmodule SharedData.Repo.Migrations.CreateChainStates do
  use Ecto.Migration

  def change do
    create table(:chain_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chain_id, :string, null: false
      add :current_step_index, :integer, default: 0
      add :current_state, :string, default: "idle"
      add :pending_order_id, :string
      add :reference_price, :decimal
      add :last_fill_price, :decimal
      add :initial_fill_price, :decimal
      add :initial_quantity, :decimal
      add :current_quantity, :decimal
      add :execution_history, :map, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      add :setting_id, references(:settings, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps()
    end

    create unique_index(:chain_states, [:setting_id, :chain_id])
    create index(:chain_states, [:current_state])
    create index(:chain_states, [:setting_id])
  end
end
