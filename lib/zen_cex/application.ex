defmodule ZenCex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Telemetry handlers disabled during rewrite
    # ZenCex.Telemetry.attach_handlers()

    children = [
      # HTTP client for API requests
      {Finch, name: ZenCex.Finch}

      # NOTE: Old Exchange modules disabled - rewriting with plugin architecture
      # See docs/cex-implementation-tasks.md for new architecture plan
      
      # Disabled during rewrite:
      # - ZenCex.RateLimit (will become per-adapter rate limiters)
      # - ZenCex.Health.Monitor (will become Core.Health)  
      # - ZenCex.Health.Startup (will become Core.Health)
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZenCex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
