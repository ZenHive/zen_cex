defmodule ZenCex.Health.Check do
  @moduledoc """
  Startup health checks for exchange connections.

  Ensures all exchange connections are healthy before the application
  fully starts. This prevents issues with authentication, rate limiting,
  and order execution that could occur with poor time synchronization.
  """

  require Logger

  @exchanges [:binance, :kraken, :deribit]
  @max_retries 3
  @retry_delay_ms 1000

  @doc """
  Performs health checks on application startup.

  Called from the application supervision tree to verify all exchanges
  are accessible and time synchronization is within acceptable limits.

  Returns:
  - `:ok` if all checks pass
  - `{:error, reason}` if critical checks fail
  """
  @spec startup_check() :: :ok | {:error, term()}
  def startup_check do
    Logger.info("[HealthCheck] Starting exchange health checks...")

    case check_all_exchanges() do
      {:ok, results} ->
        Logger.info("[HealthCheck] All exchanges healthy: #{inspect(results)}")
        :ok

      {:warning, results} ->
        Logger.warning("[HealthCheck] Some exchanges show warnings: #{inspect(results)}")
        # Allow startup with warnings but log them
        :ok

      {:critical, results} ->
        Logger.error("[HealthCheck] Critical health check failures: #{inspect(results)}")
        {:error, {:health_check_failed, results}}
    end
  end

  @doc """
  Performs health checks with retry logic.

  Retries failed checks up to max_retries times with exponential backoff.
  """
  @spec startup_check_with_retry() :: :ok | {:error, term()}
  def startup_check_with_retry do
    startup_check_with_retry(@max_retries)
  end

  defp startup_check_with_retry(0) do
    Logger.error("[HealthCheck] Health checks failed after #{@max_retries} attempts")
    {:error, :health_check_failed}
  end

  defp startup_check_with_retry(retries_left) do
    case startup_check() do
      :ok ->
        :ok

      {:error, _reason} ->
        delay = @retry_delay_ms * (@max_retries - retries_left + 1)
        Logger.warning("[HealthCheck] Retrying in #{delay}ms (#{retries_left - 1} retries left)")
        Process.sleep(delay)
        startup_check_with_retry(retries_left - 1)
    end
  end

  defp check_all_exchanges do
    alias ZenCex.Health

    # Check individual exchanges
    individual_results =
      @exchanges
      |> Enum.map(fn exchange ->
        case Health.check_exchange_sync(exchange) do
          {:ok, result} -> {exchange, result}
          {:error, reason} -> {exchange, {:error, reason}}
        end
      end)

    # Check consensus
    case Health.check_multi_exchange_consensus(@exchanges) do
      {:ok, consensus} ->
        {:ok, %{individual: Map.new(individual_results), consensus: consensus}}

      {:warning, consensus} ->
        {:warning, %{individual: Map.new(individual_results), consensus: consensus}}

      {:critical, consensus} ->
        {:critical, %{individual: Map.new(individual_results), consensus: consensus}}
    end
  end

  @doc """
  Performs a quick health check for monitoring purposes.

  This is a lighter-weight check suitable for periodic monitoring.
  """
  @spec quick_check() :: :ok | :warning | :critical
  def quick_check do
    alias ZenCex.Health

    case Health.check_multi_exchange_consensus(@exchanges) do
      {:ok, _} -> :ok
      {:warning, _} -> :warning
      {:critical, _} -> :critical
    end
  end

  @doc """
  Returns detailed health status for all exchanges.

  Useful for admin dashboards and monitoring systems.
  """
  @spec detailed_status() :: map()
  def detailed_status do
    alias ZenCex.Health

    # Get individual exchange status
    exchanges_status =
      @exchanges
      |> Enum.map(fn exchange ->
        status =
          case Health.check_exchange_sync(exchange) do
            {:ok, result} ->
              Map.put(result, :healthy, result.status == :ok)

            {:error, reason} ->
              %{
                exchange: exchange,
                healthy: false,
                error: reason,
                status: :error
              }
          end

        {exchange, status}
      end)
      |> Map.new()

    # Get consensus status
    consensus =
      case Health.check_multi_exchange_consensus(@exchanges) do
        {status, result} -> Map.put(result, :overall_status, status)
      end

    %{
      timestamp: DateTime.utc_now(),
      exchanges: exchanges_status,
      consensus: consensus,
      healthy: consensus.overall_status == :ok
    }
  end
end
