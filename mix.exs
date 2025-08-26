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
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
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
      {:tidewave, "~> 0.3.1", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      # HTTP client
      {:req, "~> 0.5.0"},
      {:finch, "~> 0.20.0"},

      # Circuit breaker (optional)
      {:req_fuse, "~> 0.3", optional: true},
      {:fuse, "~> 2.5", optional: true},

      # Debug mode (dev only, optional)
      {:curl_req, "~> 0.98", only: [:dev, :test], optional: true},

      # JSON handling
      {:jason, "~> 1.4"},

      # Financial calculations
      {:decimal, "~> 2.0"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # YAML parsing (for endpoint generation)
      {:yaml_elixir, "~> 2.9", only: :dev},

      # Testing & development
      {:plug, "~> 1.0", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [
      preferred_envs: [precommit: :test, "coveralls.html": :test]
    ]
  end

  defp aliases do
    [
      test: ["test"],
      "test.cover": ["coveralls.html"],
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
        # "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000, allowed_origins: [\"//localhost\"]) end)'"
        # ~s{run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, allowed_origins: ["//localhost", "//127.0.0.1", "//0.0.0.0", "//::1"], port: 4000) end)'}
      ],
      precommit: [
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format",
        "test --cover",
        "doctor",
        "credo --strict --all"
      ]
    ]
  end
end
