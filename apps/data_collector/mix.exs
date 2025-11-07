defmodule DataCollector.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_collector,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about configuration.
  def application do
    [
      extra_applications: [:logger],
      mod: {DataCollector.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:binance, "~> 1.0"},
      {:websockex, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.2"},
      {:phoenix_pubsub, "~> 2.1"},
      {:shared_data, in_umbrella: true}
    ]
  end
end
