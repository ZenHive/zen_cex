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

  ## ETS Table Management
  This module creates separate ETS tables for each API type to prevent contention:
  - Table naming convention: `Elixir.ZenCex.Adapters.Binance.RateLimiter.Table.{api_type}`
  - Tables are created on-demand when first accessed
  - Supported API types: `:spot`, `:sapi`, `:usdm_futures`, `:coinm_futures`, `:portfolio`
  - Each table tracks rate limit usage independently with minute-based windows
  """

  @behaviour ZenCex.Behaviors.RateLimiter

  alias ZenCex.Core.RateLimiter, as: Core

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

  # Number of minutes to keep in ETS before cleanup
  @cleanup_age_minutes 2
  # Percentage conversion
  @percentage_multiplier 100

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
      table = get_or_create_table(api_type)
      Core.check_and_increment(table, api_type, weight, get_limit_for_type(api_type))
      log_emergency_usage(api_type, weight, operation || endpoint)
      :ok
    else
      # Regular operations check against 90% capacity
      api_type = detect_api_type(endpoint)
      limit = get_limit_for_type(api_type)
      regular_limit = trunc(limit * @regular_capacity_ratio)
      table = get_or_create_table(api_type)

      # Use core module with regular capacity limit
      case Core.check_and_increment(table, api_type, weight, regular_limit) do
        :ok ->
          :ok

        {:error, _} ->
          # Rate limited - calculate retry after
          retry_after_ms = Core.calculate_retry_after(:minute)
          Logger.warning("Rate limited on #{api_type}: regular capacity exceeded")
          {:error, {:rate_limited, retry_after_ms}}
      end
    end
  end

  @impl true
  def update_from_response(%Req.Response{headers: headers} = response) do
    # Binance returns rate limit usage in headers
    headers_map = Map.new(headers)

    # Detect API type from URL if available
    api_type = detect_api_type_from_response(response)

    # Map headers to their respective API types
    header_mappings = [
      {"x-mbx-used-weight-1m", api_type, get_limit_for_type(api_type)},
      {"x-sapi-used-ip-weight-1m", :sapi, @sapi_limit}
    ]

    Enum.each(header_mappings, fn {header_name, type, limit} ->
      if weight_header = headers_map[header_name] do
        weight_value = parse_weight_header(weight_header)
        table = get_or_create_table(type)

        # Update using core module
        Core.update_from_headers(
          table,
          %{header_name => weight_header},
          &parse_weight_header/1,
          header_name
        )

        # Log usage warnings
        check_and_log_usage(type, weight_value, limit)
      end
    end)

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
          coinm_futures: build_status(:coinm_futures),
          portfolio: build_status(:portfolio)
        }

      type ->
        build_status(type)
    end
  end

  @impl true
  def reset(endpoint) do
    if endpoint do
      api_type = detect_api_type(endpoint)
      table = get_or_create_table(api_type)
      Core.reset(table, api_type)
    else
      # Reset all
      Enum.each([:spot, :sapi, :usdm_futures, :coinm_futures, :portfolio], fn api_type ->
        table = get_or_create_table(api_type)
        Core.reset(table, api_type)
      end)
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

  # Get or create table for specific API type
  defp get_or_create_table(api_type) do
    table_name = String.to_atom("#{__MODULE__}.Table.#{api_type}")
    Core.init_table(table_name)
    table_name
  end

  defp log_emergency_usage(api_type, _weight, operation) do
    Logger.debug("Emergency operation #{operation} bypassing rate limits on #{api_type}")

    # Check if we're using emergency reserve
    table = get_or_create_table(api_type)
    limit = get_limit_for_type(api_type)
    regular_limit = trunc(limit * @regular_capacity_ratio)

    case Core.get_status(table, api_type, limit, :minute) do
      %{used: used} when used > regular_limit ->
        usage_percent = round(used / limit * @percentage_multiplier)
        Logger.info("Emergency operation using reserved capacity on #{api_type}: #{usage_percent}% of total limit")

      _ ->
        :ok
    end
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
    table = get_or_create_table(api_type)

    # Get base status from core module with window in seconds
    # Binance uses minute-based rate limits (60 seconds)
    window_seconds = 60
    base_status = Core.get_status(table, api_type, limit, window_seconds)

    # Enhance with Binance-specific fields
    Map.merge(base_status, %{
      regular_limit: regular_limit,
      emergency_reserve: emergency_reserve,
      regular_usage_percent: round(base_status.used / regular_limit * @percentage_multiplier),
      in_emergency_zone: base_status.used > regular_limit
    })
  end

  @doc """
  Cleans up old entries from all API type tables.
  Should be called periodically (e.g., every minute) to prevent memory growth.
  """
  @spec cleanup_old_entries() :: non_neg_integer()
  def cleanup_old_entries do
    Enum.reduce([:spot, :sapi, :usdm_futures, :coinm_futures, :portfolio], 0, fn api_type, acc ->
      table = get_or_create_table(api_type)
      deleted = Core.cleanup_old_windows(table, @cleanup_age_minutes)
      acc + deleted
    end)
  end
end
