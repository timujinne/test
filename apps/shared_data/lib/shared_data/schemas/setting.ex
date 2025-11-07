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
    |> foreign_key_constraint(:account_id)
  end
end
