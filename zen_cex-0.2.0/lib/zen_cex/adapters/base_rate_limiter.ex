defmodule ZenCex.Adapters.BaseRateLimiter do
  @moduledoc """
  Common rate limiting patterns for all exchange adapters.

  Provides shared rate limiting logic including:
  - ETS table setup and management
  - Capacity calculations and threshold monitoring
  - Emergency operation handling
  - Time-based cleanup utilities

  ## ETS Table Management

  All exchange rate limiters should use the provided helpers for consistent
  ETS table creation and management:

      # In your rate limiter module
      defp get_or_create_table(api_type) do
        table_name = build_table_name(__MODULE__, api_type)
        setup_ets_table(table_name)
        table_name
      end

  ## Emergency Operations

  Configure emergency operations that should bypass rate limits:

      use ZenCex.Adapters.BaseRateLimiter,
        exchange: :binance,
        emergency_operations: [:cancel_order, :cancel_all_orders],
        emergency_path_patterns: ["/order", "/allOpenOrders"]

  ## Time-Based Cleanup

  Use the cleanup utilities to remove stale entries from ETS tables:

      # Cleanup entries older than 2 minutes in a minute-based system
      cleanup_old_minutes(table, current_minute, 2)

      # Cleanup entries older than 24 windows in a 5-second window system
      cleanup_old_windows(table, key_prefix, current_window, 24)
  """

  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)
    emergency_operations = Keyword.get(opts, :emergency_operations, [])
    emergency_path_patterns = Keyword.get(opts, :emergency_path_patterns, [])

    quote do
      alias ZenCex.Core.RateLimiter, as: Core

      require Logger

      # Common thresholds across all exchanges
      # Alert at 80% capacity usage
      @warning_threshold 0.80
      # Critical alert at 95% capacity
      @critical_threshold 0.95
      # Reserve 10% capacity for emergency operations
      @regular_capacity_ratio 0.90
      # Convert decimal ratios to percentages
      @percentage_multiplier 100

      @doc """
      Checks if an operation qualifies as emergency (bypass rate limits).
      """
      @spec emergency_operation?(atom() | String.t()) :: boolean()
      def emergency_operation?(operation) when is_atom(operation) do
        operation in unquote(emergency_operations)
      end

      def emergency_operation?(path) when is_binary(path) do
        Enum.any?(unquote(emergency_path_patterns), &String.contains?(path, &1))
      end

      @doc """
      Calculates capacity usage percentage.
      """
      @spec calculate_capacity_usage(number(), number()) :: float()
      def calculate_capacity_usage(current, limit) when limit > 0 do
        Float.round(current / limit * @percentage_multiplier, 1)
      end

      def calculate_capacity_usage(_, _), do: 0.0

      @doc """
      Logs capacity warnings based on usage thresholds.
      """
      @spec log_capacity_warning(float(), atom()) :: :ok
      def log_capacity_warning(usage, exchange \\ unquote(exchange)) do
        cond do
          usage >= @critical_threshold * @percentage_multiplier ->
            Logger.critical("#{exchange} rate limit: #{usage}% usage (CRITICAL)")

          usage >= @warning_threshold * @percentage_multiplier ->
            Logger.warning("#{exchange} rate limit: #{usage}% usage")

          true ->
            :ok
        end
      end

      @doc """
      Gets the reserved capacity ratio for regular operations.
      """
      @spec get_regular_capacity_ratio() :: float()
      def get_regular_capacity_ratio, do: @regular_capacity_ratio

      @doc """
      Checks if capacity is available for regular operations.
      """
      @spec has_regular_capacity?(number(), number()) :: boolean()
      def has_regular_capacity?(current, limit) do
        current < limit * @regular_capacity_ratio
      end

      @doc """
      Creates an ETS table with standard options if it doesn't exist.

      Returns the table name. If the table already exists, returns the name unchanged.
      Uses standard options: `:set`, `:public`, `:named_table`, with `write_concurrency: true`
      for high-throughput rate limiting.
      """
      @spec setup_ets_table(atom()) :: atom()
      def setup_ets_table(table_name) do
        case :ets.whereis(table_name) do
          :undefined ->
            :ets.new(table_name, [:set, :public, :named_table, write_concurrency: true])
            table_name

          _tid ->
            table_name
        end
      end

      @doc """
      Builds a standardized table name from module and api_type.

      ## Examples

          build_table_name(MyExchange.RateLimiter, :spot)
          # => :"Elixir.MyExchange.RateLimiter.Table.spot"
      """
      @spec build_table_name(module(), atom()) :: atom()
      def build_table_name(module, api_type) do
        String.to_atom("#{module}.Table.#{api_type}")
      end

      @doc """
      Cleans up old minute-based entries from ETS table.

      Used for rate limiters that track per-minute usage. Removes all entries
      older than the specified age in minutes.

      ## Parameters
        - `table` - ETS table name
        - `current_minute` - Current minute timestamp
        - `max_age_minutes` - Maximum age of entries to keep (default: 2)

      ## Examples

          current_minute = div(System.system_time(:second), 60)
          cleanup_old_minutes(table, current_minute, 2)
      """
      @spec cleanup_old_minutes(atom(), integer(), integer()) :: :ok
      def cleanup_old_minutes(table, current_minute, max_age_minutes \\ 2) do
        cutoff_minute = current_minute - max_age_minutes

        # Delete entries older than cutoff
        :ets.select_delete(table, [
          {
            {{:"$1", :"$2"}, :_},
            [{:<, :"$2", cutoff_minute}],
            [true]
          }
        ])

        :ok
      end

      @doc """
      Cleans up old window-based entries from ETS table.

      Used for rate limiters that track per-window usage (e.g., 5-second windows).
      Removes all entries older than the specified number of windows.

      ## Parameters
        - `table` - ETS table name
        - `key_prefix` - Prefix used in keys (e.g., `:bybit`)
        - `current_window` - Current window number
        - `max_age_windows` - Maximum number of windows to keep (default: 24)

      ## Examples

          current_window = div(System.system_time(:second), 5)
          cleanup_old_windows(table, :bybit, current_window, 24)
      """
      @spec cleanup_old_windows(atom(), atom(), integer(), integer()) :: :ok
      def cleanup_old_windows(table, key_prefix, current_window, max_age_windows \\ 24) do
        cutoff_window = current_window - max_age_windows

        # Delete entries older than cutoff
        :ets.select_delete(table, [
          {
            {{key_prefix, :"$1"}, :_},
            [{:<, :"$1", cutoff_window}],
            [true]
          }
        ])

        :ok
      end

      # Allow adapters to override these if needed
      defoverridable emergency_operation?: 1,
                     calculate_capacity_usage: 2,
                     log_capacity_warning: 1,
                     log_capacity_warning: 2
    end
  end
end
