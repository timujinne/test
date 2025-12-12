defmodule SharedData.Schemas.ChainState do
  @moduledoc """
  Schema for tracking conditional chain strategy state.
  Stores execution progress and allows recovery after restarts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_states ~w(idle awaiting_initial awaiting_step awaiting_branch completed error)

  schema "chain_states" do
    field :chain_id, :string
    field :current_step_index, :integer, default: 0
    field :current_state, :string, default: "idle"
    field :pending_order_id, :string
    field :reference_price, :decimal
    field :last_fill_price, :decimal
    field :initial_fill_price, :decimal
    field :initial_quantity, :decimal
    field :current_quantity, :decimal
    field :execution_history, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :setting, SharedData.Schemas.Setting

    timestamps()
  end

  @doc false
  def changeset(chain_state, attrs) do
    chain_state
    |> cast(attrs, [
      :chain_id,
      :current_step_index,
      :current_state,
      :pending_order_id,
      :reference_price,
      :last_fill_price,
      :initial_fill_price,
      :initial_quantity,
      :current_quantity,
      :execution_history,
      :started_at,
      :completed_at,
      :setting_id
    ])
    |> validate_required([:chain_id, :setting_id])
    |> validate_inclusion(:current_state, @valid_states)
    |> validate_number(:current_step_index, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:setting_id)
    |> unique_constraint([:setting_id, :chain_id])
  end

  @doc """
  Changeset for updating chain state during execution.
  """
  def update_changeset(chain_state, attrs) do
    chain_state
    |> cast(attrs, [
      :current_step_index,
      :current_state,
      :pending_order_id,
      :reference_price,
      :last_fill_price,
      :initial_fill_price,
      :current_quantity,
      :execution_history,
      :completed_at
    ])
    |> validate_inclusion(:current_state, @valid_states)
  end

  @doc """
  Adds an execution event to the history.
  """
  def add_to_history(chain_state, event_type, event_data) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    event = %{
      "type" => to_string(event_type),
      "data" => event_data,
      "timestamp" => timestamp
    }

    history = chain_state.execution_history || %{}
    events = Map.get(history, "events", [])
    updated_history = Map.put(history, "events", events ++ [event])

    change(chain_state, execution_history: updated_history)
  end
end
