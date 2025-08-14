defmodule ZenCex.Health.Startup do
  @moduledoc """
  Startup task for exchange health checks.

  This task runs after Finch is started and performs initial health checks
  on all configured exchanges.
  """

  use Task, restart: :transient
  require Logger

  def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

  def run(_arg) do
    # Wait a moment for Finch pools to be ready
    Process.sleep(1000)

    # Run health checks if enabled
    if Application.get_env(:zen_cex, :check_exchange_health_on_startup, true) do
      Logger.info("[HealthStartup] Running exchange health checks...")

      case ZenCex.Health.Check.startup_check_with_retry() do
        :ok ->
          Logger.info("[HealthStartup] All exchange health checks passed")

        {:error, reason} ->
          # Log but don't fail - let monitoring handle it
          Logger.error("[HealthStartup] Exchange health check failed: #{inspect(reason)}")
      end
    end

    :ok
  end
end
