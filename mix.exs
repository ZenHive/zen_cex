defmodule ZenCex.MixProject do
  use Mix.Project

  def project do
    [
      app: :zen_cex,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ZenCex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5.0"},
      {:finch, "~> 0.20.0"},

      # JSON handling
      {:jason, "~> 1.4"},

      # Financial calculations
      {:decimal, "~> 2.0"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # Testing & development
      {:plug, "~> 1.0", only: [:dev, :test]},
      {:mock, "~> 0.3.8", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:tidewave, "~> 0.2", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["test"],
      "test.cover": ["coveralls.html"],
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
    ]
  end
end
