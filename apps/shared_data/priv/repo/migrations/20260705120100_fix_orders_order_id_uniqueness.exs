defmodule SharedData.Repo.Migrations.FixOrdersOrderIdUniqueness do
  use Ecto.Migration

  def change do
    drop unique_index(:orders, [:order_id])

    create unique_index(:orders, [:account_id, :order_id],
             name: :orders_account_id_order_id_index
           )
  end
end
