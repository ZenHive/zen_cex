defmodule ZenCex.Telemetry do
  @moduledoc """
  Telemetry event definitions and attachments for Exchange modules.

  Provides centralized telemetry event handling for rate limiting, health checks,
  and other exchange-related metrics.
  """

  require Logger

  @doc """
  Attaches all exchange telemetry handlers.
  Should be called from Application.start/2.
  """
  @spec attach_handlers() :: :ok
  def attach_handlers do
    attach_rate_limit_handlers()
    attach_health_handlers()
    :ok
  end

  defp attach_rate_limit_handlers do
    events = [
      [:zen_cex, :exchange, :rate_limit, :check],
      [:zen_cex, :exchange, :rate_limit, :cleanup],
      [:zen_cex, :exchange, :rate_limit, :header_update]
    ]

    :telemetry.attach_many(
      "block-watch-rate-limit",
      events,
      &handle_rate_limit_event/4,
      nil
    )
  end

  defp attach_health_handlers do
    events = [
      [:zen_cex, :exchange, :health, :check],
      [:zen_cex, :exchange, :health, :consensus],
      [:zen_cex, :exchange, :health, :startup]
    ]

    :telemetry.attach_many(
      "block-watch-health",
      events,
      &handle_health_event/4,
      nil
    )
  end

  defp handle_rate_limit_event(
         [:zen_cex, :exchange, :rate_limit, :check],
         measurements,
         metadata,
         _config
       ) do
    if metadata.result == :rate_limited do
      Logger.warning(
        "Rate limit exceeded for #{metadata.exchange} #{metadata.endpoint}, weight: #{measurements.weight}"
      )
    end
  end

  defp handle_rate_limit_event(
         [:zen_cex, :exchange, :rate_limit, :cleanup],
         measurements,
         _metadata,
         _config
       ) do
    if measurements.duration_ms > 100 do
      Logger.info(
        "Rate limit cleanup took #{measurements.duration_ms}ms, cleaned #{measurements.entries_cleaned} entries"
      )
    end
  end

  defp handle_rate_limit_event(
         [:zen_cex, :exchange, :rate_limit, :header_update],
         measurements,
         metadata,
         _config
       ) do
    if measurements.new_weight > measurements.old_weight * 1.5 do
      Logger.debug(
        "Rate limit weight jump for #{metadata.exchange}: #{measurements.old_weight} -> #{measurements.new_weight}"
      )
    end
  end

  defp handle_health_event(
         [:zen_cex, :exchange, :health, :check],
         measurements,
         metadata,
         _config
       ) do
    case metadata.status do
      :critical ->
        Logger.error(
          "Exchange health critical: #{metadata.exchange}, drift: #{measurements.drift_ms}ms"
        )

      :warning ->
        Logger.warning(
          "Exchange health warning: #{metadata.exchange}, drift: #{measurements.drift_ms}ms"
        )

      _ ->
        :ok
    end
  end

  defp handle_health_event(
         [:zen_cex, :exchange, :health, :consensus],
         measurements,
         metadata,
         _config
       ) do
    if length(metadata.outliers) > 0 do
      Logger.warning(
        "Exchange consensus outliers detected: #{inspect(metadata.outliers)}, median drift: #{measurements.median_drift_ms}ms"
      )
    end
  end

  defp handle_health_event(
         [:zen_cex, :exchange, :health, :startup],
         measurements,
         metadata,
         _config
       ) do
    if metadata.success do
      Logger.info("Exchange health startup complete in #{measurements.duration_ms}ms")
    else
      Logger.error(
        "Exchange health startup failed after #{measurements.duration_ms}ms: #{metadata.reason}"
      )
    end
  end

  @doc """
  Returns telemetry event names for monitoring.
  """
  @spec event_names() :: [list(atom())]
  def event_names do
    [
      [:zen_cex, :exchange, :rate_limit, :check],
      [:zen_cex, :exchange, :rate_limit, :cleanup],
      [:zen_cex, :exchange, :rate_limit, :header_update],
      [:zen_cex, :exchange, :health, :check],
      [:zen_cex, :exchange, :health, :consensus],
      [:zen_cex, :exchange, :health, :startup]
    ]
  end
end
