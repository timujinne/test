defmodule SharedData.Trading do
  @moduledoc """
  Context для управления торговыми операциями: ордера, сделки, балансы, настройки.
  """
  
  import Ecto.Query, warn: false
  alias SharedData.Repo
  alias SharedData.Schemas.{Order, Trade, Balance, Setting}

  ## Order functions

  @doc """
  Создать ордер.
  """
  def create_order(attrs \\ %{}) do
    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Получить ордер по ID.
  """
  def get_order!(id), do: Repo.get!(Order, id)

  @doc """
  Получить ордер по order_id из Binance.
  """
  def get_order_by_binance_id(order_id) do
    Repo.get_by(Order, order_id: order_id)
  end

  @doc """
  Список всех ордеров аккаунта.
  """
  def list_account_orders(account_id) do
    Order
    |> where([o], o.account_id == ^account_id)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Список активных ордеров аккаунта.
  """
  def list_active_orders(account_id) do
    Order
    |> where([o], o.account_id == ^account_id and o.status in ["NEW", "PARTIALLY_FILLED"])
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Обновить ордер.
  """
  def update_order(%Order{} = order, attrs) do
    order
    |> Order.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Обновить статус ордера.
  """
  def update_order_status(order_id, status, filled_qty \\ nil) do
    order = get_order_by_binance_id(order_id)

    if order do
      attrs = %{status: status}
      attrs = if filled_qty, do: Map.put(attrs, :filled_qty, filled_qty), else: attrs

      update_order(order, attrs)
    else
      {:error, :not_found}
    end
  end

  ## Trade functions

  @doc """
  Создать сделку.
  """
  def create_trade(attrs \\ %{}) do
    %Trade{}
    |> Trade.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Список всех сделок аккаунта.
  """
  def list_account_trades(account_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Trade
    |> where([t], t.account_id == ^account_id)
    |> order_by([t], desc: t.timestamp)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Получить сделки по символу.
  """
  def list_trades_by_symbol(account_id, symbol, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Trade
    |> where([t], t.account_id == ^account_id and t.symbol == ^symbol)
    |> order_by([t], desc: t.timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Рассчитать общий P&L по аккаунту.
  """
  def calculate_total_pnl(account_id) do
    query =
      from t in Trade,
        where: t.account_id == ^account_id and not is_nil(t.pnl),
        select: sum(t.pnl)

    Repo.one(query) || Decimal.new(0)
  end

  @doc """
  Рассчитать P&L по символу.
  """
  def calculate_symbol_pnl(account_id, symbol) do
    query =
      from t in Trade,
        where: t.account_id == ^account_id and t.symbol == ^symbol and not is_nil(t.pnl),
        select: sum(t.pnl)

    Repo.one(query) || Decimal.new(0)
  end

  @doc """
  Статистика сделок за период.
  """
  def get_trade_statistics(account_id, from_date, to_date) do
    query =
      from t in Trade,
        where: t.account_id == ^account_id and t.timestamp >= ^from_date and t.timestamp <= ^to_date,
        select: %{
          total_trades: count(t.id),
          total_volume: sum(t.quantity),
          total_pnl: sum(t.pnl),
          avg_pnl: avg(t.pnl)
        }

    Repo.one(query)
  end

  ## Balance functions

  @doc """
  Создать или обновить баланс.
  """
  def upsert_balance(account_id, asset, free, locked) do
    case Repo.get_by(Balance, account_id: account_id, asset: asset) do
      nil ->
        %Balance{}
        |> Balance.changeset(%{
          account_id: account_id,
          asset: asset,
          free: free,
          locked: locked
        })
        |> Repo.insert()

      balance ->
        balance
        |> Balance.changeset(%{free: free, locked: locked})
        |> Repo.update()
    end
  end

  @doc """
  Получить балансы аккаунта.
  """
  def list_account_balances(account_id) do
    Balance
    |> where([b], b.account_id == ^account_id)
    |> where([b], b.total > 0)
    |> order_by([b], desc: b.total)
    |> Repo.all()
  end

  @doc """
  Получить баланс конкретного актива.
  """
  def get_balance(account_id, asset) do
    Repo.get_by(Balance, account_id: account_id, asset: asset)
  end

  @doc """
  Обновить балансы из данных Binance.
  """
  def sync_balances(account_id, binance_balances) do
    Enum.each(binance_balances, fn balance ->
      upsert_balance(
        account_id,
        balance["asset"],
        Decimal.new(balance["free"]),
        Decimal.new(balance["locked"])
      )
    end)
  end

  ## Setting functions

  @doc """
  Создать настройку стратегии.
  """
  def create_setting(account_id, attrs \\ %{}) do
    attrs = Map.put(attrs, :account_id, account_id)

    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Получить настройки аккаунта.
  """
  def list_account_settings(account_id) do
    Setting
    |> where([s], s.account_id == ^account_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Получить активную настройку.
  """
  def get_active_setting(account_id) do
    Setting
    |> where([s], s.account_id == ^account_id and s.is_active == true)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Обновить настройку.
  """
  def update_setting(%Setting{} = setting, attrs) do
    setting
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Активировать настройку (деактивирует все остальные).
  """
  def activate_setting(%Setting{} = setting) do
    Repo.transaction(fn ->
      # Деактивировать все настройки аккаунта
      from(s in Setting,
        where: s.account_id == ^setting.account_id and s.is_active == true
      )
      |> Repo.update_all(set: [is_active: false])

      # Активировать выбранную
      setting
      |> Setting.changeset(%{is_active: true})
      |> Repo.update!()
    end)
  end

  @doc """
  Удалить настройку.
  """
  def delete_setting(%Setting{} = setting) do
    Repo.delete(setting)
  end
end
