defmodule ZenCex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers
    ZenCex.Telemetry.attach_handlers()

    children = [
      # HTTP client for API requests
      {Finch, name: ZenCex.Finch},

      # Rate limiter for exchange APIs
      ZenCex.RateLimit,

      # Health monitoring for exchanges
      {ZenCex.Health.Monitor,
       exchanges: [:binance, :kraken, :deribit], check_interval: :timer.minutes(5)},

      # Startup health check
      {ZenCex.Health.Startup, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZenCex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
