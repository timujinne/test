defmodule DataCollector.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_collector,
      version: "1.0.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [summary: false]
    ]
  end

  def application do
    [
      mod: {DataCollector.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:binance, "~> 2.0"},
      {:websockex, "~> 0.4"},
      # httpoison is already included as a dependency of binance (~> 1.4)
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      # Already locked at 1.11.12 transitively (via ueberauth_apple); pinned
      # explicitly here for Coinbase's ES256 JWT auth (DataCollector.Coinbase.Auth).
      {:jose, "~> 1.11"},
      {:shared_data, in_umbrella: true}
    ]
  end
end
