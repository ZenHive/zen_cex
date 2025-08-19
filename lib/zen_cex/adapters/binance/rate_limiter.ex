defmodule ZenCex.Adapters.Binance.RateLimiter do
  @moduledoc """
  Pragmatic rate limiter for Binance REST APIs - optimized for regular trading, not HFT.

  This implementation follows a reactive approach suitable for non-HFT usage:
  - Monitors rate limit headers from responses and logs warnings
  - Does NOT maintain sliding windows or complex state
  - Relies on Req's retry mechanism for 429 responses
  - Always allows emergency operations (cancel_order)

  ## Binance Rate Limits (per minute)
  - Spot API: 1200 weight units
  - SAPI: 12000 weight units  
  - Futures API: 2400 weight units

  ## Monitoring Approach
  - Logs WARNING at 80% usage
  - Logs CRITICAL at 95% usage
  - Never blocks requests proactively (except in extreme cases)
  - Lets Req handle 429 responses with exponential backoff
  """

  @behaviour ZenCex.Behaviors.RateLimiter

  require Logger

  # API type limits per minute
  @spot_limit 1200
  @sapi_limit 12000
  @futures_limit 2400

  # Warning thresholds
  @warning_threshold 0.80
  @critical_threshold 0.95

  # Emergency operations that should never be blocked
  @emergency_operations ~w[
    /api/v3/order
    /fapi/v1/order
    /fapi/v1/allOpenOrders
  ]

  @impl true
  def check_and_increment(endpoint, weight \\ 1) do
    # For emergency operations, always allow
    if emergency_operation?(endpoint) do
      :ok
    else
      # For regular trading (non-HFT), we don't proactively block
      # Just increment counter for monitoring purposes
      api_type = detect_api_type(endpoint)
      increment_counter(api_type, weight)
      :ok
    end
  end

  @impl true
  def update_from_response(%Req.Response{headers: headers} = _response) do
    # Binance returns rate limit usage in headers
    # x-mbx-used-weight-1m: weight used in last minute (Spot)
    # x-sapi-used-ip-weight-1m: weight used in last minute (SAPI)
    # x-mbx-used-weight-1m: weight used in last minute (Futures)

    headers_map = Map.new(headers)

    # Check Spot API weight
    if spot_weight = headers_map["x-mbx-used-weight-1m"] do
      weight_value = parse_weight_header(spot_weight)
      check_and_log_usage(:spot, weight_value, @spot_limit)
    end

    # Check SAPI weight
    if sapi_weight = headers_map["x-sapi-used-ip-weight-1m"] do
      weight_value = parse_weight_header(sapi_weight)
      check_and_log_usage(:sapi, weight_value, @sapi_limit)
    end

    # Check Futures API weight (uses same header as spot but different context)
    # TODO: We'd need to detect from the request URL whether it's futures
    # TODO: For now, futures monitoring is handled by the spot check above

    :ok
  end

  @impl true
  def get_status(endpoint) do
    api_type = if endpoint, do: detect_api_type(endpoint), else: :all

    case api_type do
      :all ->
        %{
          spot: build_status(:spot),
          sapi: build_status(:sapi),
          futures: build_status(:futures)
        }

      type ->
        build_status(type)
    end
  end

  @impl true
  def reset(endpoint) do
    if endpoint do
      api_type = detect_api_type(endpoint)
      reset_counter(api_type)
    else
      # Reset all
      reset_counter(:spot)
      reset_counter(:sapi)
      reset_counter(:futures)
    end

    :ok
  end

  @impl true
  def get_limits do
    %{
      spot: %{limit: @spot_limit, window: 60},
      sapi: %{limit: @sapi_limit, window: 60},
      futures: %{limit: @futures_limit, window: 60}
    }
  end

  # Private functions

  defp emergency_operation?(endpoint) do
    # DELETE requests to order endpoints are always emergency
    String.contains?(endpoint, "/order") or
      Enum.any?(@emergency_operations, &String.contains?(endpoint, &1))
  end

  defp detect_api_type(endpoint) do
    cond do
      String.contains?(endpoint, "/sapi/") -> :sapi
      String.contains?(endpoint, "/fapi/") or String.contains?(endpoint, "/dapi/") -> :futures
      true -> :spot
    end
  end

  defp increment_counter(api_type, weight) do
    # Simple ETS counter for monitoring only
    # We don't block based on this - just track for logging
    table = get_or_create_table()
    key = {api_type, current_minute()}

    # Atomic increment
    :ets.update_counter(table, key, {2, weight}, {key, 0})
  catch
    _error, _reason ->
      # If ETS fails, don't block the request
      :ok
  end

  defp get_or_create_table do
    table_name = __MODULE__.Table

    case :ets.whereis(table_name) do
      :undefined ->
        # Create table if it doesn't exist
        :ets.new(table_name, [
          :named_table,
          :public,
          :set,
          {:write_concurrency, true}
        ])

      tid ->
        tid
    end
  end

  defp current_minute do
    # Get current minute as unix timestamp
    System.system_time(:second) |> div(60)
  end

  defp parse_weight_header(value) when is_binary(value) do
    String.to_integer(value)
  end

  defp parse_weight_header([value | _]) when is_binary(value) do
    # Sometimes headers come as lists from Req/Finch
    String.to_integer(value)
  end

  defp parse_weight_header(value) when is_integer(value) do
    value
  end

  defp check_and_log_usage(api_type, used, limit) do
    usage_percent = used / limit

    cond do
      usage_percent >= @critical_threshold ->
        Logger.critical(
          "Binance #{api_type} API at #{round(usage_percent * 100)}% of rate limit (#{used}/#{limit})"
        )

      usage_percent >= @warning_threshold ->
        Logger.warning(
          "Binance #{api_type} API at #{round(usage_percent * 100)}% of rate limit (#{used}/#{limit})"
        )

      true ->
        # Below warning threshold, optionally log debug
        Logger.debug(
          "Binance #{api_type} API usage: #{used}/#{limit} (#{round(usage_percent * 100)}%)"
        )
    end
  end

  defp build_status(api_type) do
    limit =
      case api_type do
        :spot -> @spot_limit
        :sapi -> @sapi_limit
        :futures -> @futures_limit
      end

    try do
      table = get_or_create_table()
      key = {api_type, current_minute()}

      used =
        case :ets.lookup(table, key) do
          [{^key, count}] -> count
          [] -> 0
        end

      %{
        used: used,
        limit: limit,
        window: 60,
        reset_at: (current_minute() + 1) * 60,
        usage_percent: round(used / limit * 100)
      }
    catch
      _error, _reason ->
        %{used: 0, limit: limit, window: 60, reset_at: 0, usage_percent: 0}
    end
  end

  defp reset_counter(api_type) do
    table = get_or_create_table()
    key = {api_type, current_minute()}
    :ets.delete(table, key)
  catch
    _error, _reason ->
      :ok
  end

  @doc """
  Cleans up old entries from ETS table.
  Should be called periodically (e.g., every minute) to prevent memory growth.
  """
  def cleanup_old_entries do
    table = get_or_create_table()
    current = current_minute()

    # Delete entries older than 2 minutes
    :ets.select_delete(table, [
      {{{:"$1", :"$2"}, :_}, [{:<, :"$2", current - 2}], [true]}
    ])
  catch
    _error, _reason ->
      0
  end
end
