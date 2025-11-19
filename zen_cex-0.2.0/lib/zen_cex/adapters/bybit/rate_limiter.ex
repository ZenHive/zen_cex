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

  # Maximum reasonable timestamp value (~2286 AD) to prevent overflow
  @max_reset_timestamp_ms 10_000_000_000_000

  # Minimum remaining requests (for clarity in calculations)
  @min_remaining_requests 0

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

  # Emergency operations list for membership checking

  @typedoc """
  ETS table entry formats used by the rate limiter:

  ## Rate limit tracking entries
  - `{{:bybit, window_number}, request_count}` - Tracks requests per 5-second window
    - `window_number` - Integer representing the current 5-second window (System.system_time(:second) div 5)
    - `request_count` - Number of requests made in this window

  ## Special entries
  - `{{:bybit, :next_reset}, timestamp_ms}` - Stores API-provided reset timestamp
    - `timestamp_ms` - Unix timestamp in milliseconds when rate limit resets
  """
  @type ets_entry ::
          {{:bybit, non_neg_integer()}, non_neg_integer()}
          | {{:bybit, :next_reset}, non_neg_integer()}

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

    # Atomic increment and check - avoids race conditions
    # The update_counter operation is atomic, so we increment first then check
    new_count = :ets.update_counter(table, key, {2, weight}, {key, 0})

    if new_count > regular_limit do
      # Over limit - rollback the increment
      :ets.update_counter(table, key, {2, -weight})

      # Rate limited - calculate retry after
      retry_after_ms = calculate_retry_after()
      Logger.warning("Rate limited on Bybit: regular capacity exceeded")
      {:error, {:rate_limited, retry_after_ms}}
    else
      # Within limit - request can proceed
      :ok
    end
  end

  @impl true
  def update_from_response(%Req.Response{headers: headers} = _response) do
    headers_map = Map.new(headers)

    # Try different header formats in priority order
    cond do
      headers_map["x-bapi-limit-status"] ->
        handle_bapi_headers(headers_map)

      headers_map["x-ratelimit-remaining"] ->
        handle_fallback_headers(headers_map)

      true ->
        :ok
    end
  end

  # Handle Bybit's official X-Bapi-Limit headers
  defp handle_bapi_headers(headers_map) do
    case safe_parse_header_value(headers_map["x-bapi-limit-status"]) do
      {:ok, used} ->
        limit = extract_bapi_limit(headers_map)
        # x-bapi-limit-status contains USED count, not remaining
        remaining = max(@min_remaining_requests, limit - used)
        process_rate_limit_update(remaining, limit, :bapi_headers)
        handle_reset_timestamp(headers_map)

      {:error, _reason} ->
        Logger.warning("Failed to parse Bybit rate limit headers")
    end
  end

  # Extract limit from X-Bapi-Limit header or use default
  defp extract_bapi_limit(headers_map) do
    with val when is_binary(val) <- headers_map["x-bapi-limit"],
         {:ok, parsed_limit} <- safe_parse_header_value(val) do
      parsed_limit
    else
      _ -> @bybit_limit
    end
  end

  # Handle fallback headers
  defp handle_fallback_headers(headers_map) do
    case safe_parse_header_value(headers_map["x-ratelimit-remaining"]) do
      {:ok, remaining} ->
        process_rate_limit_update(remaining, @bybit_limit, :fallback_headers)

      {:error, _reason} ->
        Logger.warning("Failed to parse fallback rate limit headers")
    end
  end

  # Process rate limit update (common logic)
  defp process_rate_limit_update(remaining, limit, source) do
    used = max(0, limit - remaining)
    table = get_or_create_table()
    key = {:bybit, get_current_window()}

    # Update ETS atomically with calculated usage
    update_rate_limit_usage(table, key, used)

    # Log usage warnings
    check_and_log_usage(used, limit)

    # Emit telemetry event for rate limit update
    :telemetry.execute(
      [:zen_cex, :bybit, :rate_limit, :updated],
      %{used: used, limit: limit, remaining: remaining},
      %{source: source}
    )
  end

  # Handle reset timestamp if present
  defp handle_reset_timestamp(headers_map) do
    reset_str = extract_reset_header_value(headers_map["x-bapi-limit-reset-timestamp"])

    case reset_str do
      nil ->
        :ok

      reset_str ->
        case parse_reset_timestamp(reset_str) do
          {:ok, reset_time_ms} ->
            process_reset_timestamp(reset_str, reset_time_ms)

          {:error, reason} ->
            Logger.warning("Failed to parse Bybit reset timestamp: #{reason}")
        end
    end
  end

  # Extract header value from various formats (headers can be strings or lists)
  defp extract_reset_header_value(nil), do: nil
  defp extract_reset_header_value([value | _]) when is_binary(value), do: value
  defp extract_reset_header_value(value) when is_binary(value), do: value
  defp extract_reset_header_value(_), do: nil

  # Process the parsed reset timestamp
  defp process_reset_timestamp(reset_str, reset_time_ms) do
    now_ms = System.system_time(:millisecond)
    backoff_ms = max(0, reset_time_ms - now_ms)

    # Store backoff information if applicable
    store_reset_if_needed(reset_time_ms, backoff_ms)

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :bybit, :rate_limit, :reset_info],
      %{
        reset_timestamp: reset_str,
        reset_time_ms: reset_time_ms,
        backoff_ms: backoff_ms
      },
      %{}
    )
  end

  # Store reset timestamp if we need to back off
  defp store_reset_if_needed(reset_time_ms, backoff_ms) when backoff_ms > 0 do
    table = get_or_create_table()
    :ets.insert(table, {{:bybit, :next_reset}, reset_time_ms})
    Logger.debug("Bybit rate limit resets in #{backoff_ms}ms (at timestamp: #{reset_time_ms})")
  end

  defp store_reset_if_needed(_reset_time_ms, _backoff_ms), do: :ok

  # Parse reset timestamp from various formats
  defp parse_reset_timestamp(timestamp_str) when is_binary(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {timestamp_ms, ""} when timestamp_ms >= 10_000_000_000 and timestamp_ms <= @max_reset_timestamp_ms ->
        # Already in milliseconds
        {:ok, timestamp_ms}

      {timestamp_s, ""} when timestamp_s > 0 and timestamp_s * 1000 <= @max_reset_timestamp_ms ->
        # In seconds, convert to milliseconds
        {:ok, timestamp_s * 1000}

      _ ->
        {:error, :invalid_format}
    end
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

  # Helper to update rate limit usage in ETS atomically
  defp update_rate_limit_usage(table, key, used) do
    # Use update_counter for truly atomic operation
    # If key doesn't exist, creates it with default {key, 0} then adds used
    :ets.update_counter(table, key, {2, used}, {key, 0})
  rescue
    ArgumentError ->
      # Fallback for older ETS versions or if table doesn't exist
      :ets.insert_new(table, {key, 0})
      :ets.update_element(table, key, {2, used})
  end

  defp emergency_operation?(endpoint, operation)

  # Check by operation atom using MapSet for O(1) lookup
  defp emergency_operation?(_endpoint, operation) when is_atom(operation) do
    operation in @emergency_operations
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
    # First check if we have a stored reset timestamp from headers
    table = get_or_create_table()
    now_ms = System.system_time(:millisecond)

    case :ets.lookup(table, {:bybit, :next_reset}) do
      [{{:bybit, :next_reset}, reset_time_ms}] when reset_time_ms > now_ms ->
        # Use the actual reset time from the API with a small buffer
        backoff_ms = reset_time_ms - now_ms + @retry_buffer_ms
        Logger.debug("Using API-provided reset time, backing off for #{backoff_ms}ms")
        backoff_ms

      _ ->
        # Fall back to calculating based on window
        current_second = System.system_time(:second)
        next_window_start = (div(current_second, @window_seconds) + 1) * @window_seconds
        retry_after_seconds = next_window_start - current_second
        # Add buffer to ensure we're in the next window
        retry_after_seconds * 1000 + @retry_buffer_ms
    end
  end

  defp safe_parse_header_value(value) when is_binary(value) do
    # Validate header length to prevent malicious injection
    if byte_size(value) > 20 do
      {:error, :header_too_long}
    else
      case Integer.parse(value) do
        {int_value, ""} when int_value >= 0 and int_value <= 1_000_000 ->
          # Reasonable bounds for rate limit values
          {:ok, int_value}

        {_int_value, ""} ->
          {:error, :value_out_of_bounds}

        _ ->
          {:error, :invalid_integer}
      end
    end
  end

  defp safe_parse_header_value([value | _]) when is_binary(value) do
    # Sometimes headers come as lists from Req/Finch
    safe_parse_header_value(value)
  end

  defp safe_parse_header_value(value) when is_integer(value) do
    {:ok, value}
  end

  defp safe_parse_header_value(_value) do
    {:error, :invalid_format}
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
    now_ms = System.system_time(:millisecond)

    # Delete entries older than cleanup age
    deleted_windows =
      :ets.select_delete(table, [
        {{{:"$1", :"$2"}, :_}, [{:<, :"$2", cutoff}], [true]}
      ])

    # Clean up expired reset timestamps (special entries)
    deleted_resets =
      :ets.select_delete(table, [
        {{{:bybit, :next_reset}, :"$1"}, [{:<, :"$1", now_ms}], [true]}
      ])

    deleted_windows + deleted_resets
  catch
    :error, :badarg ->
      # Table doesn't exist yet
      0

    :error, reason ->
      Logger.warning("Failed to cleanup old rate limit entries: #{inspect(reason)}")
      0
  end
end
