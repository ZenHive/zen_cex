defmodule ZenCex.Adapters.BaseParameterBuilder do
  @moduledoc """
  Common parameter building patterns for all exchange adapters.

  Provides shared logic for parameter filtering, normalization,
  and timestamp generation across exchanges.
  """

  defmacro __using__(opts) do
    default_recv_window = Keyword.get(opts, :default_recv_window, 5000)

    quote do
      alias ZenCex.Core.ParameterBuilder, as: Core
      alias ZenCex.Safety.ClockSync

      @default_recv_window unquote(default_recv_window)

      @doc """
      Filters and normalizes parameters for API requests.
      """
      @spec filter_and_normalize(map()) :: map()
      def filter_and_normalize(params) do
        params
        |> Core.filter_optional_params()
        |> Core.normalize_param_values()
      end

      @doc """
      Builds a query string from parameters.
      Delegates to Core for consistent formatting.
      """
      @spec build_query_string(map()) :: String.t()
      defdelegate build_query_string(params), to: Core

      @doc """
      Adds timestamp if not already present.
      """
      @spec add_timestamp_if_missing(map(), atom()) :: map()
      def add_timestamp_if_missing(params, exchange) do
        if Map.has_key?(params, "timestamp") do
          params
        else
          timestamp = generate_timestamp_for_exchange(exchange)
          Map.put(params, "timestamp", timestamp)
        end
      end

      @doc """
      Gets the default receive window for this adapter.
      """
      @spec get_default_recv_window() :: integer()
      def get_default_recv_window, do: @default_recv_window

      # Private helpers

      defp generate_timestamp_for_exchange(exchange) do
        try_result =
          try do
            ClockSync.now_with_offset(exchange)
          rescue
            # ArgumentError is raised when ClockSync hasn't synchronized for this exchange yet
            # In that case, fall back to system time as a reasonable default
            ArgumentError ->
              System.system_time(:millisecond)
          end

        to_string(try_result)
      end

      defp ensure_string_value(value) when is_binary(value), do: value
      defp ensure_string_value(value), do: to_string(value)

      # Allow adapters to override these if needed
      defoverridable filter_and_normalize: 1,
                     add_timestamp_if_missing: 2,
                     get_default_recv_window: 0
    end
  end
end
