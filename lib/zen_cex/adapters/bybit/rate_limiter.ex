defmodule ZenCex.Adapters.Bybit.RateLimiter do
  @moduledoc """
  Pragmatic rate limiter for Bybit v5 REST API - optimized for regular trading, not HFT.

  This implementation follows a reactive approach suitable for non-HFT usage:
  - Monitors rate limit headers from responses and logs warnings
  - Does NOT maintain sliding windows or complex state
  - Relies on Req's retry mechanism for 429 responses
  - **Emergency Bypass**: Always allows critical safety operations (cancel_order, cancel_all, close_position)
  - **Reserved Capacity**: Reserves 10% of rate limit capacity for emergency operations

  ## Bybit Rate Limits
  Bybit v5 uses a 5-second rolling window with 600 requests per window.
  - Regular capacity: 540 requests (90% of total)
  - Emergency reserve: 60 requests (10% of total)

  ## Emergency Operations
  Emergency operations that bypass normal rate limits:
  - Order cancellation (single, batch, all)
  - Position closing
  - Risk management operations

  ## Monitoring Approach
  - Logs WARNING at 80% of regular capacity
  - Logs CRITICAL at 95% of regular capacity
  - Emergency operations always proceed even at 100% usage
  - Lets Req handle 429 responses with exponential backoff

  ## ETS Table Management
  This module creates a single ETS table for tracking rate limits:
  - Table name: `Elixir.ZenCex.Adapters.Bybit.RateLimiter.Table`
  - Table is created on-demand when first accessed
  - Uses 5-second time windows for rate limit tracking
  """

  @behaviour ZenCex.Behaviors.RateLimiter

  alias ZenCex.Core.RateLimiter, as: Core

  require Logger

  # Bybit v5 rate limit per 5-second window
  @bybit_limit 600
  @window_seconds 5

  # Warning thresholds (based on regular capacity, not total)
  @warning_threshold 0.80
  @critical_threshold 0.95

  # Emergency capacity reservation (10% of total limit)
  @regular_capacity_ratio 0.90

  # Number of windows to keep in ETS before cleanup
  # 24 * 5 seconds = 2 minutes
  @cleanup_age_windows 24
  # Percentage conversion
  @percentage_multiplier 100

  # Buffer added to retry_after to ensure we're in the next window
  @retry_buffer_ms 100

  # Emergency operations that should never be blocked
  # These patterns match operations for order cancellation and position closing
  @emergency_path_patterns ~w[
    /order/cancel
    /cancel
    /cancel-all
    /cancel-batch
    /position/close
    /position/set-leverage
    /position/switch-mode
  ]

  # Emergency operation names (matched against operation atom)
  @emergency_operations [
    :cancel_order,
    :cancel_all_orders,
    :cancel_multiple_orders,
    :cancel_batch_orders,
    :close_position,
    :close_all_positions,
    :switch_position_mode,
    :set_leverage,
    :spot_cancel_order,
    :spot_cancel_all_orders,
    :linear_cancel_order,
    :linear_cancel_all_orders,
    :inverse_cancel_order,
    :inverse_cancel_all_orders,
    :option_cancel_order,
    :option_cancel_all_orders
  ]

  # MapSet for O(1) emergency operation lookup
  @emergency_operations_set MapSet.new(@emergency_operations)

  @impl true
  @spec check_and_increment(String.t() | atom(), non_neg_integer()) ::
          :ok | {:error, :rate_limited} | {:error, {:rate_limited, non_neg_integer()}}
  def check_and_increment(endpoint, weight \\ 1) do
    check_and_increment(endpoint, weight, nil)
  end

  @doc """
  Enhanced version that accepts operation atom for better emergency detection.

  ## Parameters
    - `endpoint` - The API endpoint path or identifier
    - `weight` - The rate limit weight for this operation (default: 1)
    - `operation` - Optional atom identifying the operation type for emergency detection
  """
  @spec check_and_increment(String.t() | atom(), non_neg_integer(), atom() | nil) ::
          :ok | {:error, :rate_limited} | {:error, {:rate_limited, non_neg_integer()}}
  def check_and_increment(endpoint, weight, operation) do
    if emergency_operation?(endpoint, operation) do
      handle_emergency_operation(endpoint, weight, operation)
    else
      handle_regular_operation(endpoint, weight)
    end
  catch
    :error, :badarg ->
      # ETS table doesn't exist or bad argument
      Logger.warning("ETS table error in rate limiter, allowing request")
      :ok

    :error, reason ->
      # Other ETS errors
      Logger.warning("ETS operation failed in rate limiter: #{inspect(reason)}, allowing request")
      :ok
  end

  # Handle emergency operations that bypass rate limits
  defp handle_emergency_operation(endpoint, weight, operation) do
    table = get_or_create_table()
    key = {:bybit, get_current_window()}

    # Always increment for emergency operations (no limit check)
    :ets.update_counter(table, key, {2, weight}, {key, 0})
    log_emergency_usage(weight, operation || endpoint)
    :ok
  end

  # Handle regular operations with rate limit checking
  defp handle_regular_operation(_endpoint, weight) do
    regular_limit = trunc(@bybit_limit * @regular_capacity_ratio)
    table = get_or_create_table()
    key = {:bybit, get_current_window()}

    # Check if adding weight would exceed regular limit
    if check_regular_capacity(table, key, weight, regular_limit) do
      # Atomic increment
      :ets.update_counter(table, key, {2, weight}, {key, 0})
      :ok
    else
      # Rate limited - calculate retry after
      retry_after_ms = calculate_retry_after()
      Logger.warning("Rate limited on Bybit: regular capacity exceeded")
      {:error, {:rate_limited, retry_after_ms}}
    end
  end

  # Check if operation can proceed within regular capacity
  defp check_regular_capacity(table, key, weight, limit) do
    current_usage =
      case :ets.lookup(table, key) do
        [{^key, count}] -> count
        [] -> 0
      end

    current_usage + weight <= limit
  end

  @impl true
  def update_from_response(%Req.Response{headers: headers} = _response) do
    # Bybit v5 doesn't provide rate limit usage in headers
    # It uses status code 10006 for rate limit errors
    # We could track request counts locally if needed

    # Check for rate limit info in headers (if Bybit adds them)
    headers_map = Map.new(headers)

    # TODO: Monitor Bybit documentation for official rate limit headers
    # Currently checking common headers: x-ratelimit-limit, x-ratelimit-remaining, x-ratelimit-reset
    if remaining_header = headers_map["x-ratelimit-remaining"] do
      remaining = parse_header_value(remaining_header)
      used = @bybit_limit - remaining
      table = get_or_create_table()
      key = {:bybit, get_current_window()}

      # Update ETS with calculated usage
      :ets.insert(table, {key, used})

      # Log usage warnings
      check_and_log_usage(used, @bybit_limit)
    end

    :ok
  end

  @impl true
  def get_status(_endpoint) do
    # Bybit has a single unified rate limit, endpoint param is ignored
    build_status()
  end

  @impl true
  def reset(_endpoint) do
    # Reset the single table - clear current window
    table = get_or_create_table()
    key = {:bybit, get_current_window()}
    :ets.delete(table, key)
    :ok
  end

  @impl true
  def get_limits do
    %{
      bybit: %{limit: @bybit_limit, window: @window_seconds}
    }
  end

  # Private functions

  defp emergency_operation?(endpoint, operation)

  # Check by operation atom using MapSet for O(1) lookup
  defp emergency_operation?(_endpoint, operation) when is_atom(operation) do
    MapSet.member?(@emergency_operations_set, operation)
  end

  # Check by endpoint path patterns
  defp emergency_operation?(endpoint, _operation) when is_binary(endpoint) do
    # Check if endpoint contains cancel or close keywords
    String.contains?(endpoint, "cancel") or
      String.contains?(endpoint, "close") or
      Enum.any?(@emergency_path_patterns, &String.contains?(endpoint, &1))
  end

  # Default to false
  defp emergency_operation?(_endpoint, _operation), do: false

  # Get or create table for Bybit
  defp get_or_create_table do
    table_name = String.to_atom("#{__MODULE__}.Table")
    Core.init_table(table_name)
    table_name
  end

  defp log_emergency_usage(_weight, operation) do
    Logger.debug("Emergency operation #{operation} bypassing rate limits on Bybit")

    # Check if we're using emergency reserve
    table = get_or_create_table()
    regular_limit = trunc(@bybit_limit * @regular_capacity_ratio)
    key = {:bybit, get_current_window()}

    case :ets.lookup(table, key) do
      [{^key, used}] when used > regular_limit ->
        usage_percent = round(used / @bybit_limit * @percentage_multiplier)
        Logger.info("Emergency operation using reserved capacity on Bybit: #{usage_percent}% of total limit")

      _ ->
        :ok
    end
  end

  defp get_current_window do
    # Bybit uses 5-second windows
    :second |> System.system_time() |> div(@window_seconds)
  end

  defp calculate_retry_after do
    # Calculate milliseconds until next 5-second window
    current_second = System.system_time(:second)
    next_window_start = (div(current_second, @window_seconds) + 1) * @window_seconds
    retry_after_seconds = next_window_start - current_second
    # Add buffer to ensure we're in the next window
    retry_after_seconds * 1000 + @retry_buffer_ms
  end

  defp parse_header_value(value) when is_binary(value) do
    String.to_integer(value)
  end

  defp parse_header_value([value | _]) when is_binary(value) do
    # Sometimes headers come as lists from Req/Finch
    String.to_integer(value)
  end

  defp parse_header_value(value) when is_integer(value) do
    value
  end

  defp check_and_log_usage(used, limit) do
    # Calculate usage against regular capacity (90% of total)
    regular_limit = trunc(limit * @regular_capacity_ratio)
    regular_usage_percent = used / regular_limit
    total_usage_percent = used / limit

    cond do
      # Check if we're into emergency reserve territory
      used > regular_limit ->
        Logger.critical(
          "Bybit API using EMERGENCY RESERVE: #{round(total_usage_percent * @percentage_multiplier)}% of total limit (#{used}/#{limit})"
        )

      regular_usage_percent >= @critical_threshold ->
        Logger.warning(
          "Bybit API at #{round(regular_usage_percent * @percentage_multiplier)}% of regular capacity (#{used}/#{regular_limit})"
        )

      regular_usage_percent >= @warning_threshold ->
        Logger.info(
          "Bybit API at #{round(regular_usage_percent * @percentage_multiplier)}% of regular capacity (#{used}/#{regular_limit})"
        )

      true ->
        # Below warning threshold, optionally log debug
        Logger.debug(
          "Bybit API usage: #{used}/#{regular_limit} regular capacity (#{round(regular_usage_percent * @percentage_multiplier)}%)"
        )
    end
  end

  defp build_status do
    regular_limit = trunc(@bybit_limit * @regular_capacity_ratio)
    emergency_reserve = @bybit_limit - regular_limit
    table = get_or_create_table()

    # Get current usage from table directly for 5-second window
    key = {:bybit, get_current_window()}

    used =
      case :ets.lookup(table, key) do
        [{^key, count}] -> count
        [] -> 0
      end

    # Build status map
    %{
      used: used,
      limit: @bybit_limit,
      window: @window_seconds,
      reset_at: (get_current_window() + 1) * @window_seconds,
      usage_percent: round(used / @bybit_limit * @percentage_multiplier),
      at_limit: used >= @bybit_limit,
      regular_limit: regular_limit,
      emergency_reserve: emergency_reserve,
      regular_usage_percent: round(used / regular_limit * @percentage_multiplier),
      in_emergency_zone: used > regular_limit
    }
  end

  @doc """
  Cleans up old entries from the ETS table.
  Should be called periodically (e.g., every minute) to prevent memory growth.
  """
  @spec cleanup_old_entries() :: non_neg_integer()
  def cleanup_old_entries do
    table = get_or_create_table()
    current = get_current_window()
    cutoff = current - @cleanup_age_windows

    # Delete entries older than cleanup age
    :ets.select_delete(table, [
      {{{:"$1", :"$2"}, :_}, [{:<, :"$2", cutoff}], [true]}
    ])
  catch
    :error, :badarg ->
      # Table doesn't exist yet
      0

    :error, reason ->
      Logger.warning("Failed to cleanup old rate limit entries: #{inspect(reason)}")
      0
  end
end
