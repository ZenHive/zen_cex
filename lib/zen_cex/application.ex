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
      # HTTP client for API requests - Req's connection pooling backend
      {Finch, name: ZenCex.Finch},

      # Order safety for idempotency checks (manages ETS table lifecycle)
      ZenCex.Safety.OrderSafety,

      # Clock synchronization for accurate exchange timestamps
      ZenCex.Safety.ClockSync,

      # Binance rate limiter cleanup process
      ZenCex.Adapters.Binance.RateLimiterCleanup

      # NOTE: Following Req-centric architecture:
      # - No Core.Supervisor needed (Req handles connection lifecycle)
      # - Rate limiting via ETS tables with atomic operations (no GenServer)
      # - Auth as stateless Req middleware steps (except Deribit OAuth)
      # - TODO: Add Deribit.Auth GenServer when OAuth is implemented
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZenCex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
