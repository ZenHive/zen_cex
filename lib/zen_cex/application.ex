defmodule ZenCex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Telemetry handlers disabled during rewrite
    # ZenCex.Telemetry.attach_handlers()

    base_children = [
      # HTTP client for API requests - Req's connection pooling backend
      {Finch, name: ZenCex.Finch},

      # Market data cache GenServer (manages ETS lifecycle)
      ZenCex.Core.Cache,

      # Order safety for idempotency checks (manages ETS table lifecycle)
      ZenCex.Safety.OrderSafety,

      # Clock synchronization for accurate exchange timestamps
      ZenCex.Safety.ClockSync

      # NOTE: Following Req-centric architecture:
      # - No Core.Supervisor needed (Req handles connection lifecycle)
      # - Rate limiting is now reactive (no ETS tracking or cleanup needed)
      # - Auth as stateless Req middleware steps (except Deribit OAuth)
      # - TODO: Add Deribit.Auth GenServer when OAuth is implemented
    ]

    # Add debug table based on configuration
    children =
      if Application.get_env(:zen_cex, :enable_debug_table, false) do
        base_children ++ [ZenCex.Core.DebugTable]
      else
        base_children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ZenCex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
