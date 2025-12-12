defmodule BinanceSystem.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "1.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp deps do
    [
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      # Heroicons for icon support
      {:heroicons,
        github: "tailwindlabs/heroicons",
        tag: "v2.2.0",
        sparse: "optimized",
        app: false,
        compile: false,
        depth: 1}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run apps/shared_data/priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": [
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end

  defp releases do
    [
      binance_system: [
        version: "1.0.0",
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
