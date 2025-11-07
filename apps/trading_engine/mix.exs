defmodule TradingEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :trading_engine,
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
      mod: {TradingEngine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:shared_data, in_umbrella: true},
      {:data_collector, in_umbrella: true}
    ]
  end
end
