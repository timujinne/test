defmodule SharedData.Settings do
  @moduledoc """
  Context module for managing trading strategy settings.
  """

  import Ecto.Query, warn: false
  alias SharedData.Repo
  alias SharedData.Schemas.{Setting, Account}

  @doc """
  Lists all settings/strategies for accounts belonging to a user.
  """
  def list_user_strategies(user_id) do
    query =
      Setting
      |> join(:inner, [s], a in Account, on: s.account_id == a.id)
      |> order_by([s, a], [desc: s.is_active, asc: s.strategy_name])
      |> preload(:account)

    query =
      if is_nil(user_id) do
        where(query, [s, a], is_nil(a.user_id))
      else
        where(query, [s, a], a.user_id == ^user_id)
      end

    Repo.all(query)
  end

  @doc """
  Lists all settings for a specific account.
  """
  def list_settings_by_account(account_id) do
    Setting
    |> where([s], s.account_id == ^account_id)
    |> order_by([s], [desc: s.is_active, asc: s.strategy_name])
    |> preload(:account)
    |> Repo.all()
  end

  @doc """
  Gets a single setting by ID.
  """
  def get_setting(id) do
    Setting
    |> Repo.get(id)
    |> Repo.preload(:account)
  end

  @doc """
  Gets a single setting by ID, scoped to a specific user's accounts.
  """
  def get_setting_by_user(id, user_id) do
    query =
      Setting
      |> join(:inner, [s], a in Account, on: s.account_id == a.id)
      |> where([s, a], s.id == ^id)
      |> preload(:account)

    query =
      if is_nil(user_id) do
        where(query, [s, a], is_nil(a.user_id))
      else
        where(query, [s, a], a.user_id == ^user_id)
      end

    Repo.one(query)
  end

  @doc """
  Creates a setting/strategy.
  """
  def create_setting(attrs \\ %{}) do
    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a setting/strategy.
  """
  def update_setting(%Setting{} = setting, attrs) do
    setting
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a setting/strategy.
  """
  def delete_setting(%Setting{} = setting) do
    Repo.delete(setting)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking setting changes.
  """
  def change_setting(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  @doc """
  Activates a strategy.
  """
  def activate_setting(%Setting{} = setting) do
    update_setting(setting, %{is_active: true})
  end

  @doc """
  Deactivates a strategy.
  """
  def deactivate_setting(%Setting{} = setting) do
    update_setting(setting, %{is_active: false})
  end

  @doc """
  Returns available strategy types with their default configurations.
  """
  def available_strategies do
    [
      %{
        name: "naive",
        label: "Naive",
        description: "Simple buy-low, sell-high strategy. Good for beginners.",
        default_config: %{
          "symbol" => "BTCUSDT",
          "buy_threshold" => -0.01,
          "sell_threshold" => 0.01,
          "trade_amount" => 100
        }
      },
      %{
        name: "grid",
        label: "Grid Trading",
        description: "Place buy and sell orders at different price levels.",
        default_config: %{
          "symbol" => "BTCUSDT",
          "grid_levels" => 10,
          "grid_spacing" => 0.01,
          "amount_per_grid" => 50
        }
      },
      %{
        name: "dca",
        label: "DCA",
        description: "Dollar Cost Averaging - buy at regular intervals.",
        default_config: %{
          "symbol" => "BTCUSDT",
          "interval_hours" => 24,
          "amount_per_buy" => 100,
          "max_buys" => 30
        }
      }
    ]
  end

  @doc """
  Gets the default configuration for a strategy type.
  """
  def default_config_for(strategy_name) do
    available_strategies()
    |> Enum.find(fn s -> s.name == strategy_name end)
    |> case do
      nil -> %{}
      strategy -> strategy.default_config
    end
  end

  @doc """
  Lists all active settings with preloaded account and credentials.
  Used by StrategyManager on startup to restore running strategies.
  """
  def list_active_settings do
    Setting
    |> where([s], s.is_active == true)
    |> preload(account: :api_credential)
    |> Repo.all()
  end

  @doc """
  Gets a single setting with preloaded account and credentials.
  """
  def get_setting_with_credentials(id) do
    Setting
    |> where([s], s.id == ^id)
    |> preload(account: :api_credential)
    |> Repo.one()
  end

  @doc """
  Returns list of available trading symbols.
  """
  def available_symbols do
    [
      "BTCUSDT",
      "ETHUSDT",
      "BNBUSDT",
      "SOLUSDT",
      "XRPUSDT",
      "ADAUSDT",
      "DOGEUSDT",
      "DOTUSDT",
      "MATICUSDT",
      "LINKUSDT"
    ]
  end
end
