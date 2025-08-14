defmodule ZenCex.RateLimit do
  @moduledoc """
  Rate limiting module for exchange API calls using ETS atomic counters.

  Implements per-exchange rate limiting with partitioned ETS tables for optimal performance.
  Uses atomic counter operations to handle high-concurrency scenarios without GenServer bottlenecks.

  ## Features
  - Atomic ETS counters for lock-free rate limiting
  - Per-exchange table partitioning for performance
  - True sliding window for Binance (tracks per-second buckets over 60 seconds)
  - Automatic cleanup of old windows to prevent memory growth
  - Support for different time windows (per-second, per-minute)
  - Weight-based tracking for operations with different costs
  - Telemetry events for monitoring and alerting
  - Monotonic time for elapsed measurements
  - Header-based reconciliation for accurate Binance weight tracking

  ## Exchange Limits
  - Binance Spot: 1200 weight/minute (sliding window)
  - Binance Futures: 2400 weight/minute (sliding window)
  - Kraken: 15 requests/second (starter tier)
  - Deribit: 20 requests/second

  ## Implementation Details
  - Binance uses true sliding window: maintains 60 per-second buckets
  - Kraken/Deribit use discrete second windows
  - Cleanup process runs every 60 seconds
  - Tables are partitioned by exchange for optimal concurrent access

  ## Telemetry Events
  - `[:zen_cex, :exchange, :rate_limit, :check]` - Emitted on rate limit checks
  - `[:zen_cex, :exchange, :rate_limit, :cleanup]` - Emitted on window cleanup
  - `[:zen_cex, :exchange, :rate_limit, :header_update]` - Emitted when headers update limits
  """
  use GenServer
  require Logger

  @cleanup_interval :timer.seconds(60)
  @table_opts [:set, :public, :named_table, write_concurrency: true, read_concurrency: true]

  # API functions

  @doc """
  Starts the rate limiter process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks and increments the rate limit counter for an exchange.

  Returns `:ok` if the request is allowed, `{:error, :rate_limited}` if limit exceeded.
  """
  @spec check_and_increment(atom(), String.t(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check_and_increment(exchange, endpoint, weight \\ 1) do
    table = table_for(exchange, endpoint)
    ensure_table_exists(table)

    {window_key, limit} = get_window_and_limit(exchange, endpoint)

    # Atomic check and increment
    case increment_if_allowed(table, window_key, weight, limit) do
      :ok ->
        emit_telemetry(exchange, endpoint, weight, :ok)
        :ok

      {:error, :rate_limited} = error ->
        emit_telemetry(exchange, endpoint, weight, :rate_limited)
        error
    end
  end

  @doc """
  Returns the current usage and limit for an exchange.
  For Binance, calculates the sliding window total.
  """
  @spec get_usage(atom()) :: {non_neg_integer(), non_neg_integer()}
  def get_usage(exchange_type) do
    table = table_name_for_type(exchange_type)
    ensure_table_exists(table)

    case exchange_type do
      :binance_spot ->
        now = System.system_time(:second)
        total = calculate_sliding_window_total(table, :binance_spot, now)
        {total, 1200}

      :binance_futures ->
        now = System.system_time(:second)
        total = calculate_sliding_window_total(table, :binance_futures, now)
        {total, 2400}

      _ ->
        # For non-Binance exchanges, use simple lookup
        exchange = exchange_from_type(exchange_type)
        {window_key, limit} = get_window_and_limit(exchange, endpoint_for_type(exchange_type))

        current =
          case :ets.lookup(table, window_key) do
            [{^window_key, count}] -> count
            [] -> 0
          end

        {current, limit}
    end
  end

  @doc """
  Returns seconds until rate limit window reset.
  Uses monotonic time for precise duration calculations.
  """
  @spec reset_time(atom()) :: non_neg_integer()
  def reset_time(exchange_type) do
    exchange = exchange_from_type(exchange_type)

    case window_type(exchange) do
      :second ->
        1

      :minute ->
        # Use system time for window alignment
        now = System.system_time(:second)
        60 - rem(now, 60)
    end
  end

  @doc """
  Updates rate limit counters from response headers.
  """
  @spec update_from_headers(atom(), keyword() | map()) :: :ok
  def update_from_headers(exchange, headers) do
    headers = normalize_headers(headers)

    case exchange do
      :binance ->
        if weight = headers["x-mbx-used-weight-1m"] do
          update_weight_from_header(exchange, weight)
        end

      :binance_futures ->
        # Binance futures uses same header format as spot
        if weight = headers["x-mbx-used-weight-1m"] do
          update_weight_from_header(exchange, weight)
        end

      :kraken ->
        if limit = headers["x-ratelimit-limit"] do
          # Could update tier information here
          Logger.debug("Kraken rate limit: #{limit}")
        end

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Returns the ETS table name for an exchange.
  Public for testing purposes.
  """
  @spec table_for(atom()) :: atom()
  def table_for(exchange) do
    case exchange do
      :binance -> :rate_limits_binance_spot
      :kraken -> :rate_limits_kraken
      :deribit -> :rate_limits_deribit
      other -> :"rate_limits_#{other}"
    end
  end

  @doc """
  Returns the ETS table name for an exchange and endpoint.
  Routes Binance futures endpoints to a separate table.
  """
  @spec table_for(atom(), String.t()) :: atom()
  def table_for(:binance, "/fapi" <> _rest), do: :rate_limits_binance_futures
  def table_for(exchange, _endpoint), do: table_for(exchange)

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for each exchange
    create_tables()

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_windows()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp create_tables do
    tables = [
      :rate_limits_binance_spot,
      :rate_limits_binance_futures,
      :rate_limits_kraken,
      :rate_limits_deribit
    ]

    Enum.each(tables, fn table ->
      :ets.new(table, @table_opts)
    end)
  end

  defp ensure_table_exists(table) do
    case :ets.info(table) do
      :undefined ->
        try do
          :ets.new(table, @table_opts)
        rescue
          ArgumentError ->
            # Table was created by another process concurrently
            :ok
        end

      _ ->
        :ok
    end
  end

  defp get_window_and_limit(:binance, "/fapi" <> _rest) do
    # Binance futures - per-second bucket for sliding window, 2400 limit
    now = System.system_time(:second)
    {{:binance_futures, now}, 2400}
  end

  defp get_window_and_limit(:binance, _endpoint) do
    # Binance spot - per-second bucket for sliding window, 1200 limit
    now = System.system_time(:second)
    {{:binance_spot, now}, 1200}
  end

  defp get_window_and_limit(:binance_futures, _endpoint) do
    # Binance futures - per-second bucket for sliding window, 2400 limit
    now = System.system_time(:second)
    {{:binance_futures, now}, 2400}
  end

  defp get_window_and_limit(:kraken, _endpoint) do
    # Kraken - per second window, 15 limit
    now = System.system_time(:second)
    {{:kraken, now}, 15}
  end

  defp get_window_and_limit(:deribit, _endpoint) do
    # Deribit - per second window, 20 limit
    now = System.system_time(:second)
    {{:deribit, now}, 20}
  end

  defp get_window_and_limit(exchange, _endpoint) do
    # Default - per minute window, 1200 limit
    now = System.system_time(:second)
    window_minute = div(now, 60)
    {{exchange, window_minute}, 1200}
  end

  defp increment_if_allowed(table, key, weight, limit) do
    case key do
      {:binance_spot, _second} ->
        # For Binance, use sliding window
        increment_sliding_window(table, :binance_spot, weight, limit)

      {:binance_futures, _second} ->
        # For Binance futures, use sliding window
        increment_sliding_window(table, :binance_futures, weight, limit)

      _ ->
        # For others, use simple window
        increment_simple_window(table, key, weight, limit)
    end
  end

  defp increment_simple_window(table, key, weight, limit) do
    # Use atomic update_counter with initial value
    current = :ets.update_counter(table, key, {2, weight}, {key, 0})

    if current <= limit do
      :ok
    else
      # Rollback the increment
      :ets.update_counter(table, key, {2, -weight})
      {:error, :rate_limited}
    end
  rescue
    ArgumentError ->
      # Table doesn't exist, create entry
      :ets.insert(table, {key, weight})

      if weight <= limit do
        :ok
      else
        {:error, :rate_limited}
      end
  end

  defp increment_sliding_window(table, exchange_type, weight, limit) do
    now = System.system_time(:second)
    # Calculate total weight over last 60 seconds
    total_weight = calculate_sliding_window_total(table, exchange_type, now)

    if total_weight + weight <= limit do
      # Add weight to current second bucket
      key = {exchange_type, now}
      :ets.update_counter(table, key, {2, weight}, {key, 0})
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp calculate_sliding_window_total(table, exchange_type, now) do
    # Sum weights from the last 60 seconds
    cutoff = now - 60

    # Match all entries for this exchange type from the last 60 seconds
    # Pattern: {{exchange_type, timestamp}, weight}
    match_spec = [
      {{{exchange_type, :"$1"}, :"$2"}, [{:>, :"$1", cutoff}], [:"$2"]}
    ]

    :ets.select(table, match_spec)
    |> Enum.sum()
  rescue
    _ -> 0
  end

  defp cleanup_old_windows do
    tables = [
      :rate_limits_binance_spot,
      :rate_limits_binance_futures,
      :rate_limits_kraken,
      :rate_limits_deribit
    ]

    now = System.system_time(:second)
    start_time = System.monotonic_time(:millisecond)

    cleaned_count =
      Enum.reduce(tables, 0, fn table, acc ->
        if :ets.info(table) != :undefined do
          acc + cleanup_table(table, now)
        else
          acc
        end
      end)

    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:zen_cex, :exchange, :rate_limit, :cleanup],
      %{duration_ms: duration, entries_cleaned: cleaned_count},
      %{}
    )
  end

  defp cleanup_table(table, now) do
    # Different cutoff times based on window type
    cutoff_time =
      case table do
        # Keep 10 seconds for Kraken
        :rate_limits_kraken -> now - 10
        # Keep 10 seconds for Deribit
        :rate_limits_deribit -> now - 10
        # Keep 70 seconds for Binance (60 second window + buffer)
        :rate_limits_binance_spot -> now - 70
        :rate_limits_binance_futures -> now - 70
        # Default: Keep 2 minutes
        _ -> now - 120
      end

    # Delete old entries and return count
    # Pattern matches {exchange_type, timestamp} keys where timestamp < cutoff
    :ets.select_delete(table, [
      {{{:_, :"$1"}, :_}, [{:<, :"$1", cutoff_time}], [true]}
    ])
  rescue
    _ -> 0
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp window_type(:kraken), do: :second
  defp window_type(:deribit), do: :second
  defp window_type(_), do: :minute

  defp table_name_for_type(:binance_spot), do: :rate_limits_binance_spot
  defp table_name_for_type(:binance_futures), do: :rate_limits_binance_futures
  defp table_name_for_type(:kraken), do: :rate_limits_kraken
  defp table_name_for_type(:deribit), do: :rate_limits_deribit
  defp table_name_for_type(_), do: :rate_limits_unknown

  defp exchange_from_type(:binance_spot), do: :binance
  defp exchange_from_type(:binance_futures), do: :binance
  defp exchange_from_type(:kraken), do: :kraken
  defp exchange_from_type(:deribit), do: :deribit
  defp exchange_from_type(_), do: :unknown

  defp endpoint_for_type(:binance_futures), do: "/fapi/v1/order"
  defp endpoint_for_type(_), do: "/api/v3/order"

  defp normalize_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), v} end)
    |> Map.new()
  end

  defp update_weight_from_header(exchange, weight_value) do
    # Handle both string and list formats (headers can be ["value"] or "value")
    weight_str =
      case weight_value do
        [value | _] when is_binary(value) -> value
        value when is_binary(value) -> value
        _ -> nil
      end

    if weight_str do
      case Integer.parse(weight_str) do
        {header_weight, _} ->
          table = table_for(exchange)
          ensure_table_exists(table)
          now = System.system_time(:second)

          # Calculate current sliding window total
          exchange_type =
            if table == :rate_limits_binance_futures, do: :binance_futures, else: :binance_spot

          current_total = calculate_sliding_window_total(table, exchange_type, now)

          # If header reports higher usage, reconcile by adding the difference
          if header_weight > current_total do
            difference = header_weight - current_total
            key = {exchange_type, now}
            :ets.update_counter(table, key, {2, difference}, {key, 0})

            Logger.debug(
              "[#{exchange}] Rate limit reconciliation: local=#{current_total}, " <>
                "server=#{header_weight}, adjustment=+#{difference}"
            )

            :telemetry.execute(
              [:zen_cex, :exchange, :rate_limit, :header_update],
              %{old_weight: current_total, new_weight: header_weight, adjustment: difference},
              %{exchange: exchange}
            )
          end

        _ ->
          :ok
      end
    end
  end

  defp emit_telemetry(exchange, endpoint, weight, result) do
    :telemetry.execute(
      [:zen_cex, :exchange, :rate_limit, :check],
      %{weight: weight},
      %{
        exchange: exchange,
        endpoint: endpoint,
        result: result
      }
    )
  end
end
