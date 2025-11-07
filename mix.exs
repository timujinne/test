defmodule BinanceSystem.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run apps/shared_data/priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": [
        "cmd --cd apps/dashboard_web/assets npm run deploy",
        "phx.digest"
      ]
    ]
  end

  defp releases do
    [
      binance_system: [
        version: "0.1.0",
        applications: [
          shared_data: :permanent,
          data_collector: :permanent,
          trading_engine: :permanent,
          dashboard_web: :permanent
        ]
      ]
    ]
  end
end
