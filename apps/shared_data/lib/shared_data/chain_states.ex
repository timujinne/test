defmodule SharedData.ChainStates do
  @moduledoc """
  Context module for managing conditional chain strategy states.
  """

  import Ecto.Query, warn: false
  alias SharedData.Repo
  alias SharedData.Schemas.{ChainState, Setting}

  @doc """
  Creates a chain state.
  """
  def create_chain_state(attrs \\ %{}) do
    %ChainState{}
    |> ChainState.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single chain state by ID.
  """
  def get_chain_state(id) do
    ChainState
    |> Repo.get(id)
    |> Repo.preload(:setting)
  end

  @doc """
  Gets a chain state by setting_id.
  Returns the most recent chain state for the setting.
  """
  def get_chain_state_by_setting(setting_id) do
    ChainState
    |> where([cs], cs.setting_id == ^setting_id)
    |> order_by([cs], desc: cs.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:setting)
  end

  @doc """
  Gets a chain state by setting_id and chain_id.
  """
  def get_chain_state_by_chain_id(setting_id, chain_id) do
    ChainState
    |> where([cs], cs.setting_id == ^setting_id and cs.chain_id == ^chain_id)
    |> Repo.one()
    |> Repo.preload(:setting)
  end

  @doc """
  Updates a chain state.
  """
  def update_chain_state(%ChainState{} = chain_state, attrs) do
    chain_state
    |> ChainState.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a chain state.
  """
  def delete_chain_state(%ChainState{} = chain_state) do
    Repo.delete(chain_state)
  end

  @doc """
  Lists all chain states for an account.
  Returns chain states ordered by most recent first.
  """
  def list_chain_states_by_account(account_id) do
    ChainState
    |> join(:inner, [cs], s in Setting, on: cs.setting_id == s.id)
    |> where([cs, s], s.account_id == ^account_id)
    |> order_by([cs, s], desc: cs.inserted_at)
    |> preload(:setting)
    |> Repo.all()
  end

  @doc """
  Lists all active (non-completed) chain states.
  Used for recovery after system restart.
  """
  def list_active_chain_states do
    ChainState
    |> where([cs], cs.current_state != "completed" and cs.current_state != "error")
    |> preload(setting: [account: :api_credential])
    |> Repo.all()
  end
end
