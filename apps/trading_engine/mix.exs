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
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {TradingEngine.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:decimal, "~> 2.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:shared_data, in_umbrella: true},
      {:data_collector, in_umbrella: true}
    ]
  end
end
