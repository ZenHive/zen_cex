defmodule ZenCex.MixProject do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :zen_cex,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      source_url: "https://github.com/ZenHive/zen_cex",
      homepage_url: "https://github.com/ZenHive/zen_cex",
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
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

  defp description do
    """
    A comprehensive Elixir library for cryptocurrency exchange integrations with REST and WebSocket support.
    Provides unified API access to Binance, Bybit, and Deribit exchanges with built-in rate limiting, clock sync, and safety features.
    """
  end

  defp package do
    [
      name: "zen_cex",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/ZenHive/zen_cex",
        "Changelog" => "https://github.com/ZenHive/zen_cex/blob/main/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "docs/TELEMETRY.md"],
      source_ref: "v#{@version}",
      formatters: ["html"]
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
      {:tidewave, "~> 0.5.0", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      # HTTP client
      {:req, "~> 0.5.0"},
      {:finch, "~> 0.20.0"},

      # WebSocket client
      {:zen_websocket, git: "https://github.com/ZenHive/zen_websocket.git", branch: "main"},

      # Circuit breaker
      {:req_fuse, "~> 0.3"},
      {:fuse, "~> 2.5"},

      # Debug mode (optional)
      {:curl_req, "~> 0.98", optional: true},

      # JSON handling
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # YAML parsing (for endpoint generation)
      {:yaml_elixir, "~> 2.9", only: :dev},

      # Testing & development
      {:plug, "~> 1.16"},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
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
      "test.cover": ["cmd MIX_ENV=test mix coveralls"],
      "test.cover.html": ["cmd MIX_ENV=test mix coveralls.html"],
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4001) end)'"
        # "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000, allowed_origins: [\"//localhost\"]) end)'"
        # ~s{run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000, allowed_origins: ["//localhost", "//127.0.0.1", "//0.0.0.0", "//::1"]) end)'}
      ],
      # Quick precommit for fast iteration during development
      precommit: [
        "compile --warning-as-errors",
        "format",
        "credo --strict --all"
      ],
      # Full precommit with all checks including tests
      "precommit.full": [
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format",
        "test",
        "doctor",
        "credo --strict --all"
      ],
      # Precommit with test coverage analysis
      "precommit.cover": [
        "precommit.full",
        "test --cover"
      ]
    ]
  end
end
