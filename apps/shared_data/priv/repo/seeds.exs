# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     SharedData.Repo.insert!(%SharedData.Schemas.User{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias SharedData.Repo
alias SharedData.Schemas.{User, Setting}

# Create a demo user for development
case Repo.get_by(User, email: "demo@example.com") do
  nil ->
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: "demo@example.com",
        username: "demo",
        password: "demo123456",
        is_active: true
      })
      |> Repo.insert()

    # Create default settings for the demo user
    Repo.insert!(%Setting{
      user_id: user.id,
      key: "trading_strategy",
      value: %{
        "strategy" => "naive",
        "enabled" => false
      },
      category: "trading"
    })

    Repo.insert!(%Setting{
      user_id: user.id,
      key: "risk_management",
      value: %{
        "max_position_size_percent" => 2.0,
        "stop_loss_percent" => 2.0,
        "take_profit_percent" => 3.0
      },
      category: "risk_management"
    })

    IO.puts("Demo user created: demo@example.com / demo123456")

  _user ->
    IO.puts("Demo user already exists")
end
