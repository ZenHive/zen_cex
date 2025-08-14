defmodule ZenCex.Health.Monitor do
  @moduledoc """
  Supervised GenServer that performs periodic health checks every 30 seconds.

  Monitors exchange time synchronization and raises alerts when drift
  exceeds configured thresholds. This is critical for maintaining accurate
  order execution and preventing authentication failures.
  """

  use GenServer
  require Logger

  alias ZenCex.Health

  # 30 seconds
  @default_interval_ms 30_000
  @exchanges [:binance, :kraken, :deribit]

  # Client API

  @doc """
  Starts the health monitor.

  ## Options
  - `:interval_ms` - Check interval in milliseconds (default: 30000)
  - `:exchanges` - List of exchanges to monitor (default: [:binance, :kraken, :deribit])
  - `:warning_ms` - Warning threshold (default: 300)
  - `:critical_ms` - Critical threshold (default: 500)
  - `:name` - GenServer name (default: __MODULE__)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current health status from the monitor.
  """
  @spec get_status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_status(server \\ __MODULE__) do
    GenServer.call(server, :get_status)
  end

  @doc """
  Forces an immediate health check.
  """
  @spec check_now(GenServer.server()) :: :ok
  def check_now(server \\ __MODULE__) do
    GenServer.cast(server, :check_now)
  end

  @doc """
  Updates the monitoring configuration.
  """
  @spec update_config(GenServer.server(), keyword()) :: :ok
  def update_config(server \\ __MODULE__, opts) do
    GenServer.call(server, {:update_config, opts})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      exchanges: Keyword.get(opts, :exchanges, @exchanges),
      warning_ms: Keyword.get(opts, :warning_ms, 300),
      critical_ms: Keyword.get(opts, :critical_ms, 500),
      last_check: nil,
      last_status: nil,
      check_count: 0,
      error_count: 0,
      warning_count: 0,
      critical_count: 0
    }

    # Schedule first check immediately
    send(self(), :perform_check)

    {:ok, state}
  end

  @impl true
  def handle_info(:perform_check, state) do
    # Perform the health check
    new_state = perform_health_check(state)

    # Schedule next check
    Process.send_after(self(), :perform_check, state.interval_ms)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      last_check: state.last_check,
      last_status: state.last_status,
      check_count: state.check_count,
      error_count: state.error_count,
      warning_count: state.warning_count,
      critical_count: state.critical_count,
      interval_ms: state.interval_ms,
      exchanges: state.exchanges
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:update_config, opts}, _from, state) do
    new_state =
      state
      |> Map.merge(Map.new(opts))

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:check_now, state) do
    new_state = perform_health_check(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp perform_health_check(state) do
    check_opts = [
      warning_ms: state.warning_ms,
      critical_ms: state.critical_ms
    ]

    {status, result} = Health.check_multi_exchange_consensus(state.exchanges, check_opts)

    # Log based on status
    case status do
      :ok ->
        Logger.debug("[HealthMonitor] All exchanges healthy")

      :warning ->
        Logger.warning("[HealthMonitor] Time drift warning: #{inspect(result)}")
        alert_warning(result)

      :critical ->
        Logger.error("[HealthMonitor] Critical time drift detected: #{inspect(result)}")
        alert_critical(result)
    end

    # Update state with results
    state
    |> Map.put(:last_check, System.system_time(:millisecond))
    |> Map.put(:last_status, {status, result})
    |> Map.update(:check_count, 1, &(&1 + 1))
    |> update_counters(status)
  end

  defp update_counters(state, :ok), do: state

  defp update_counters(state, :warning) do
    Map.update(state, :warning_count, 1, &(&1 + 1))
  end

  defp update_counters(state, :critical) do
    Map.update(state, :critical_count, 1, &(&1 + 1))
  end

  defp alert_warning(result) do
    # TODO: Integrate with alerting system (e.g., send to monitoring service)
    # TODO: For now, just log the warning
    case result[:consensus][:outliers] do
      [] ->
        Logger.warning("[HealthMonitor] General time drift warning")

      outliers ->
        Logger.warning("[HealthMonitor] Outlier exchanges detected: #{inspect(outliers)}")
    end

    # Publish event for other systems to react
    :telemetry.execute(
      [:zen_cex, :health, :warning],
      %{count: 1},
      %{result: result}
    )
  end

  defp alert_critical(result) do
    # TODO: Integrate with alerting system (e.g., PagerDuty, SMS, etc.)
    # TODO: For now, log critically
    Logger.error("[HealthMonitor] CRITICAL: Time synchronization failure!")

    case result[:failed_exchanges] do
      [] ->
        Logger.error("[HealthMonitor] Critical drift on all exchanges")

      failed ->
        Logger.error("[HealthMonitor] Failed exchanges: #{inspect(failed)}")
    end

    # Publish critical event
    :telemetry.execute(
      [:zen_cex, :health, :critical],
      %{count: 1},
      %{result: result}
    )

    # Could trigger circuit breaker or pause trading here
    maybe_pause_trading(result)
  end

  defp maybe_pause_trading(_result) do
    # TODO: Implement trading pause logic if critical drift is detected
    # This would integrate with the order management system
    Logger.error("[HealthMonitor] Consider pausing trading due to time sync issues")

    # Example of what this might look like:
    # if result[:consensus][:median_drift_ms] > 1000 do
    #   BlockWatch.Trading.pause_all("Critical time drift detected")
    # end
  end
end
