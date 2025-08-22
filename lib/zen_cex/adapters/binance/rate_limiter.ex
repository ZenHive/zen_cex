defmodule ZenCex.Adapters.Binance.RateLimiter do
  @moduledoc """
  Pragmatic rate limiter for Binance REST APIs - optimized for regular trading, not HFT.

  This implementation follows a reactive approach suitable for non-HFT usage:
  - Monitors rate limit headers from responses and logs warnings
  - Does NOT maintain sliding windows or complex state
  - Relies on Req's retry mechanism for 429 responses
  - **Emergency Bypass**: Always allows critical safety operations (cancel_order, cancel_all, close_position)
  - **Reserved Capacity**: Reserves 10% of rate limit capacity for emergency operations

  ## Binance Rate Limits (per minute)
  - Spot API: 1200 weight units (1080 regular, 120 emergency reserve)
  - SAPI: 12000 weight units (10800 regular, 1200 emergency reserve)  
  - USD-M Futures: 2400 weight units (2160 regular, 240 emergency reserve)
  - COIN-M Futures: 2400 weight units (2160 regular, 240 emergency reserve)
  - Portfolio Margin: 3000 weight units (2700 regular, 300 emergency reserve)

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
  """

  @behaviour ZenCex.Behaviors.RateLimiter

  require Logger

  # API type limits per minute
  @spot_limit 1200
  @sapi_limit 12_000
  @usdm_futures_limit 2400
  @coinm_futures_limit 2400
  @portfolio_margin_limit 3000

  # Warning thresholds (based on regular capacity, not total)
  @warning_threshold 0.80
  @critical_threshold 0.95

  # Emergency capacity reservation (10% of total limit)
  @regular_capacity_ratio 0.90

  # Time conversion constants
  @seconds_per_minute 60
  # Number of minutes to keep in ETS before cleanup
  @cleanup_age_minutes 2
  # Next minute offset for reset calculation
  @next_minute_offset 1
  # Percentage conversion
  @percentage_multiplier 100
  # Retry buffer in milliseconds
  @retry_buffer_ms 100

  # Emergency operations that should never be blocked
  # These patterns match DELETE operations for order cancellation and position closing
  @emergency_path_patterns ~w[
    /order
    /allOpenOrders
    /openOrders
    /batchOrders
    /orderList
    /position/risk
    /position/margin
  ]

  # Emergency operation names (matched against operation atom)
  @emergency_operations [
    :cancel_order,
    :cancel_all_orders,
    :cancel_multiple_orders,
    :cancel_all_open_orders,
    :close_position,
    :close_all_positions,
    :cancel_batch_orders,
    :cancel_orderList,
    :cancel_all_cm_open_orders,
    :cancel_all_um_open_orders,
    :cancel_margin_account_order,
    :cancel_margin_account_all_open_orders_on_a_symbol
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
  """
  @spec check_and_increment(String.t() | atom(), non_neg_integer(), atom() | nil) ::
          :ok | {:error, :rate_limited} | {:error, {:rate_limited, non_neg_integer()}}
  def check_and_increment(endpoint, weight, operation) do
    # Check if this is an emergency operation
    is_emergency = emergency_operation?(endpoint, operation)

    if is_emergency do
      # Emergency operations always proceed
      api_type = detect_api_type(endpoint)
      increment_counter(api_type, weight, :emergency)
      Logger.debug("Emergency operation #{operation || endpoint} bypassing rate limits")
      :ok
    else
      # Regular operations check against 90% capacity
      api_type = detect_api_type(endpoint)

      # Check if we're within regular capacity limits
      if within_regular_capacity?(api_type, weight) do
        increment_counter(api_type, weight, :regular)
        :ok
      else
        # Rate limited - calculate retry after
        retry_after_ms = calculate_retry_after(api_type)
        Logger.warning("Rate limited on #{api_type}: regular capacity exceeded")
        {:error, {:rate_limited, retry_after_ms}}
      end
    end
  end

  @impl true
  def update_from_response(%Req.Response{headers: headers} = response) do
    # Binance returns rate limit usage in headers
    # x-mbx-used-weight-1m: weight used in last minute (Spot/Futures)
    # x-sapi-used-ip-weight-1m: weight used in last minute (SAPI)
    # Note: Futures uses same header name as Spot but has different limits

    headers_map = Map.new(headers)

    # Detect API type from URL if available
    api_type = detect_api_type_from_response(response)

    # Check Spot/Futures API weight (same header, different limits)
    if weight_header = headers_map["x-mbx-used-weight-1m"] do
      weight_value = parse_weight_header(weight_header)

      case api_type do
        :usdm_futures ->
          check_and_log_usage(:usdm_futures, weight_value, @usdm_futures_limit)

        :coinm_futures ->
          check_and_log_usage(:coinm_futures, weight_value, @coinm_futures_limit)

        :portfolio ->
          check_and_log_usage(:portfolio, weight_value, @portfolio_margin_limit)

        _ ->
          # Default to spot for regular API endpoints
          check_and_log_usage(:spot, weight_value, @spot_limit)
      end
    end

    # Check SAPI weight (separate header)
    if sapi_weight = headers_map["x-sapi-used-ip-weight-1m"] do
      weight_value = parse_weight_header(sapi_weight)
      check_and_log_usage(:sapi, weight_value, @sapi_limit)
    end

    :ok
  end

  # Helper to detect API type from response URL
  defp detect_api_type_from_response(%Req.Response{} = response) do
    # Try to get the request URL from the response
    # Req stores the original request in the response private field
    case response do
      %{private: %{req_url: url}} when is_binary(url) ->
        detect_api_type(url)

      _ ->
        # Fallback to :spot if we can't determine
        :spot
    end
  end

  @impl true
  def get_status(endpoint) do
    api_type = if endpoint, do: detect_api_type(endpoint), else: :all

    case api_type do
      :all ->
        %{
          spot: build_status(:spot),
          sapi: build_status(:sapi),
          usdm_futures: build_status(:usdm_futures),
          coinm_futures: build_status(:coinm_futures)
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
      reset_counter(:usdm_futures)
      reset_counter(:coinm_futures)
    end

    :ok
  end

  @impl true
  def get_limits do
    %{
      spot: %{limit: @spot_limit, window: 60},
      sapi: %{limit: @sapi_limit, window: 60},
      usdm_futures: %{limit: @usdm_futures_limit, window: 60},
      coinm_futures: %{limit: @coinm_futures_limit, window: 60},
      portfolio: %{limit: @portfolio_margin_limit, window: 60}
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
    # Check if any emergency pattern is in the endpoint
    Enum.any?(@emergency_path_patterns, &String.contains?(endpoint, &1))
  end

  # Default to false
  defp emergency_operation?(_endpoint, _operation), do: false

  defp within_regular_capacity?(api_type, weight) do
    limit = get_limit_for_type(api_type)
    regular_limit = trunc(limit * @regular_capacity_ratio)

    table = get_or_create_table()
    key = {api_type, current_minute()}

    current_usage =
      case :ets.lookup(table, key) do
        [{^key, count}] -> count
        [] -> 0
      end

    # Check if adding this weight would exceed regular capacity
    current_usage + weight <= regular_limit
  end

  defp calculate_retry_after(_api_type) do
    # Calculate how long until the next minute (rate limit reset)
    current_second = System.system_time(:second)
    next_minute = (div(current_second, @seconds_per_minute) + 1) * @seconds_per_minute
    retry_after_seconds = next_minute - current_second

    # Convert to milliseconds and add small buffer
    retry_after_seconds * 1000 + @retry_buffer_ms
  end

  defp get_limit_for_type(api_type) do
    case api_type do
      :spot -> @spot_limit
      :sapi -> @sapi_limit
      :usdm_futures -> @usdm_futures_limit
      :coinm_futures -> @coinm_futures_limit
      :portfolio -> @portfolio_margin_limit
    end
  end

  defp detect_api_type(endpoint) do
    cond do
      String.contains?(endpoint, "/sapi/") -> :sapi
      String.contains?(endpoint, "/fapi/") -> :usdm_futures
      String.contains?(endpoint, "/dapi/") -> :coinm_futures
      String.contains?(endpoint, "/papi/") -> :portfolio
      true -> :spot
    end
  end

  defp increment_counter(api_type, weight, type) do
    # Track usage for monitoring and capacity management
    table = get_or_create_table()
    key = {api_type, current_minute()}

    # Atomic increment
    :ets.update_counter(table, key, {2, weight}, {key, 0})

    # Log if emergency operation is using reserved capacity
    if type == :emergency do
      current_usage =
        case :ets.lookup(table, key) do
          [{^key, count}] -> count
          [] -> weight
        end

      limit = get_limit_for_type(api_type)
      regular_limit = trunc(limit * @regular_capacity_ratio)

      if current_usage > regular_limit do
        usage_percent = round(current_usage / limit * @percentage_multiplier)
        Logger.info("Emergency operation using reserved capacity on #{api_type}: #{usage_percent}% of total limit")
      end
    end
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
    :second |> System.system_time() |> div(@seconds_per_minute)
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
    # Calculate usage against regular capacity (90% of total)
    regular_limit = trunc(limit * @regular_capacity_ratio)
    regular_usage_percent = used / regular_limit
    total_usage_percent = used / limit

    cond do
      # Check if we're into emergency reserve territory
      used > regular_limit ->
        Logger.critical(
          "Binance #{api_type} API using EMERGENCY RESERVE: #{round(total_usage_percent * @percentage_multiplier)}% of total limit (#{used}/#{limit})"
        )

      regular_usage_percent >= @critical_threshold ->
        Logger.warning(
          "Binance #{api_type} API at #{round(regular_usage_percent * @percentage_multiplier)}% of regular capacity (#{used}/#{regular_limit})"
        )

      regular_usage_percent >= @warning_threshold ->
        Logger.info(
          "Binance #{api_type} API at #{round(regular_usage_percent * @percentage_multiplier)}% of regular capacity (#{used}/#{regular_limit})"
        )

      true ->
        # Below warning threshold, optionally log debug
        Logger.debug(
          "Binance #{api_type} API usage: #{used}/#{regular_limit} regular capacity (#{round(regular_usage_percent * @percentage_multiplier)}%)"
        )
    end
  end

  defp build_status(api_type) do
    limit = get_limit_for_type(api_type)
    regular_limit = trunc(limit * @regular_capacity_ratio)
    emergency_reserve = limit - regular_limit

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
        regular_limit: regular_limit,
        emergency_reserve: emergency_reserve,
        window: @seconds_per_minute,
        reset_at: (current_minute() + @next_minute_offset) * @seconds_per_minute,
        usage_percent: round(used / limit * @percentage_multiplier),
        regular_usage_percent: round(used / regular_limit * @percentage_multiplier),
        in_emergency_zone: used > regular_limit
      }
    catch
      _error, _reason ->
        %{
          used: 0,
          limit: limit,
          regular_limit: regular_limit,
          emergency_reserve: emergency_reserve,
          window: @seconds_per_minute,
          reset_at: 0,
          usage_percent: 0,
          regular_usage_percent: 0,
          in_emergency_zone: false
        }
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
  @spec cleanup_old_entries() :: non_neg_integer()
  def cleanup_old_entries do
    table = get_or_create_table()
    current = current_minute()

    # Delete entries older than cleanup age
    :ets.select_delete(table, [
      {{{:"$1", :"$2"}, :_}, [{:<, :"$2", current - @cleanup_age_minutes}], [true]}
    ])
  catch
    _error, _reason ->
      0
  end
end
