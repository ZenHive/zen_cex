defmodule ZenCex.Adapters.BaseRateLimiter do
  @moduledoc """
  Common rate limiting patterns for all exchange adapters.

  Provides shared rate limiting logic including capacity calculations,
  threshold monitoring, and emergency operation handling.
  """

  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)
    emergency_operations = Keyword.get(opts, :emergency_operations, [])
    emergency_path_patterns = Keyword.get(opts, :emergency_path_patterns, [])

    quote do
      alias ZenCex.Core.RateLimiter, as: Core

      require Logger

      # Common thresholds across all exchanges
      @warning_threshold 0.80
      @critical_threshold 0.95
      @regular_capacity_ratio 0.90
      @percentage_multiplier 100

      @doc """
      Checks if an operation qualifies as emergency (bypass rate limits).
      """
      @spec is_emergency_operation?(atom() | String.t()) :: boolean()
      def is_emergency_operation?(operation) when is_atom(operation) do
        operation in unquote(emergency_operations)
      end

      def is_emergency_operation?(path) when is_binary(path) do
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

      # Allow adapters to override these if needed
      defoverridable is_emergency_operation?: 1,
                     calculate_capacity_usage: 2,
                     log_capacity_warning: 1,
                     log_capacity_warning: 2
    end
  end
end
