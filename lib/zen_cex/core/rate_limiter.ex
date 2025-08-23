defmodule ZenCex.Core.RateLimiter do
  @moduledoc """
  Common ETS-based rate limiter operations for all exchanges.

  This module provides generic rate limiting functionality that can be used
  by exchange-specific rate limiters. It handles ETS table management,
  atomic counter operations, and time window calculations.

  ## Features
  - Atomic weight checking and incrementing using ETS
  - Time window-based rate limiting (minute-based)
  - Header-based usage tracking from API responses
  - Automatic cleanup of expired entries
  - Status monitoring and reporting
  - Configurable limits per API type
  """

  require Logger

  # Time conversion constants
  @seconds_per_minute 60
  # Number of minutes to keep in ETS before cleanup
  @default_cleanup_age_minutes 2
  # Retry buffer in milliseconds
  @default_retry_buffer_ms 100
  # Percentage conversion
  @percentage_multiplier 100

  @type api_type :: atom()
  @type table_ref :: :ets.tid() | atom()
  @type weight :: non_neg_integer()
  @type usage_threshold :: float()

  @doc """
  Initializes an ETS table with proper options for rate limiting.

  ## Parameters
  - `table_name`: Name of the ETS table to create
  - `opts`: Optional ETS options (defaults to [:named_table, :public, :set, {:write_concurrency, true}])

  ## Returns
  - ETS table reference or existing table if already created
  """
  @spec init_table(atom(), keyword()) :: table_ref()
  def init_table(table_name, opts \\ []) do
    default_opts = [:named_table, :public, :set, {:write_concurrency, true}]
    ets_opts = default_opts ++ opts

    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, ets_opts)

      _tid ->
        table_name
    end
  end

  @doc """
  Atomically checks if a request would exceed the limit and increments if allowed.

  ## Parameters
  - `table`: ETS table reference
  - `api_type`: API type identifier (e.g., :spot, :futures)
  - `weight`: Request weight to add
  - `limit`: Maximum allowed weight in current time window

  ## Returns
  - `:ok` if within limits and counter incremented
  - `{:error, :rate_limited}` if limit would be exceeded
  """
  @spec check_and_increment(table_ref(), api_type(), weight(), non_neg_integer()) ::
          :ok | {:error, :rate_limited}
  def check_and_increment(table, api_type, weight, limit) do
    key = {api_type, get_current_window(:minute)}

    # Get current usage
    current_usage =
      case :ets.lookup(table, key) do
        [{^key, count}] -> count
        [] -> 0
      end

    # Check if adding weight would exceed limit
    if current_usage + weight <= limit do
      # Atomic increment
      :ets.update_counter(table, key, {2, weight}, {key, 0})
      :ok
    else
      {:error, :rate_limited}
    end
  catch
    _error, _reason ->
      # If ETS fails, allow request to proceed
      Logger.warning("ETS operation failed in rate limiter, allowing request")
      :ok
  end

  @doc """
  Updates rate limit tracking from API response headers.

  ## Parameters
  - `table`: ETS table reference
  - `api_type`: API type to update
  - `headers`: Map of response headers
  - `header_name`: Name of the header containing usage info

  ## Returns
  - `:ok` after updating tracking data
  """
  @spec update_from_headers(table_ref(), api_type(), map(), String.t()) :: :ok
  def update_from_headers(table, api_type, headers, header_name) do
    if usage_header = headers[header_name] do
      weight_value = parse_weight_header(usage_header)
      key = {api_type, get_current_window(:minute)}

      # Update ETS with server-reported usage
      :ets.insert(table, {key, weight_value})
    end

    :ok
  catch
    _error, _reason ->
      Logger.warning("Failed to update rate limit from headers")
      :ok
  end

  @doc """
  Removes expired entries from the ETS table to prevent memory growth.

  ## Parameters
  - `table`: ETS table reference
  - `cleanup_age_minutes`: How many minutes of history to keep (default: 2)

  ## Returns
  - Number of entries deleted
  """
  @spec cleanup_old_windows(table_ref(), non_neg_integer()) :: non_neg_integer()
  def cleanup_old_windows(table, cleanup_age_minutes \\ @default_cleanup_age_minutes) do
    current = get_current_window(:minute)
    cutoff = current - cleanup_age_minutes

    # Delete entries older than cleanup age
    :ets.select_delete(table, [
      {{{:"$1", :"$2"}, :_}, [{:<, :"$2", cutoff}], [true]}
    ])
  catch
    _error, _reason ->
      Logger.warning("Failed to cleanup old rate limit entries")
      0
  end

  @doc """
  Gets the current time window identifier.

  ## Parameters
  - `unit`: Time unit (:second, :minute, :hour)

  ## Returns
  - Integer timestamp for the current window
  """
  @spec get_current_window(:second | :minute | :hour) :: integer()
  def get_current_window(unit) do
    divisor =
      case unit do
        :second -> 1
        :minute -> @seconds_per_minute
        :hour -> @seconds_per_minute * 60
      end

    :second |> System.system_time() |> div(divisor)
  end

  @doc """
  Gets current status for monitoring and debugging.

  ## Parameters
  - `table`: ETS table reference
  - `api_type`: API type to check
  - `limit`: Maximum limit for this API type
  - `window_seconds`: Time window in seconds (default: 60)

  ## Returns
  - Map with current usage, limit, percentages, and reset time
  """
  @spec get_status(table_ref(), api_type(), non_neg_integer(), non_neg_integer()) :: map()
  def get_status(table, api_type, limit, window_seconds \\ @seconds_per_minute) do
    key = {api_type, get_current_window(:minute)}

    used =
      case :ets.lookup(table, key) do
        [{^key, count}] -> count
        [] -> 0
      end

    %{
      used: used,
      limit: limit,
      window: window_seconds,
      reset_at: (get_current_window(:minute) + 1) * @seconds_per_minute,
      usage_percent: round(used / limit * @percentage_multiplier),
      at_limit: used >= limit
    }
  catch
    _error, _reason ->
      %{
        used: 0,
        limit: limit,
        window: window_seconds,
        reset_at: 0,
        usage_percent: 0,
        at_limit: false
      }
  end

  @doc """
  Resets rate limit counters for an API type.

  ## Parameters
  - `table`: ETS table reference
  - `api_type`: API type to reset, or `:all` to reset everything

  ## Returns
  - `:ok`
  """
  @spec reset(table_ref(), api_type() | :all) :: :ok
  def reset(table, :all) do
    :ets.delete_all_objects(table)
    :ok
  catch
    _error, _reason ->
      :ok
  end

  def reset(table, api_type) do
    key = {api_type, get_current_window(:minute)}
    :ets.delete(table, key)
    :ok
  catch
    _error, _reason ->
      :ok
  end

  @doc """
  Calculates retry-after time in milliseconds.

  ## Parameters
  - `window_unit`: Time unit for the rate limit window (:minute, :second)
  - `buffer_ms`: Additional buffer time in milliseconds (default: 100)

  ## Returns
  - Milliseconds until the next window starts
  """
  @spec calculate_retry_after(:minute | :second, non_neg_integer()) :: non_neg_integer()
  def calculate_retry_after(window_unit, buffer_ms \\ @default_retry_buffer_ms) do
    current_second = System.system_time(:second)

    next_reset =
      case window_unit do
        :minute ->
          (div(current_second, @seconds_per_minute) + 1) * @seconds_per_minute

        :second ->
          current_second + 1
      end

    retry_after_seconds = next_reset - current_second
    retry_after_seconds * 1000 + buffer_ms
  end

  # Private helper functions

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

  defp parse_weight_header(_value) do
    Logger.warning("Unable to parse rate limit header value")
    0
  end
end
