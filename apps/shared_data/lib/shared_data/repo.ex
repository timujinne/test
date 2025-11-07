defmodule SharedData.Repo do
  use Ecto.Repo,
    otp_app: :shared_data,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_type, config) do
    {:ok, config}
  end
end
