defmodule SharedData.Schemas.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "settings" do
    field :strategy_name, :string
    field :config, :map
    field :is_active, :boolean, default: false

    belongs_to :account, SharedData.Schemas.Account

    timestamps()
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:strategy_name, :config, :is_active, :account_id])
    |> validate_required([:strategy_name, :config, :account_id])
    |> validate_inclusion(:strategy_name, ["naive", "grid", "dca"])
    |> validate_config_has_symbol()
    |> foreign_key_constraint(:account_id)
  end

  # Validates that config contains a "symbol" field
  defp validate_config_has_symbol(changeset) do
    case get_field(changeset, :config) do
      nil ->
        changeset

      config when is_map(config) ->
        if Map.has_key?(config, "symbol") or Map.has_key?(config, :symbol) do
          changeset
        else
          add_error(changeset, :config, "must include 'symbol' field")
        end

      _ ->
        add_error(changeset, :config, "must be a map")
    end
  end
end
