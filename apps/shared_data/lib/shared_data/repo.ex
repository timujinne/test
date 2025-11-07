defmodule SharedData.Repo do
  use Ecto.Repo,
    otp_app: :shared_data,
    adapter: Ecto.Adapters.Postgres
end
