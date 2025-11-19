defmodule ZenCex.Adapters.Binance.ParameterBuilder do
  @moduledoc """
  Binance-specific parameter management and query string construction.

  This module handles Binance-specific parameter requirements:
  - Binance-specific parameter ordering (standard params → timestamp → recvWindow)
  - Timing parameter management with ClockSync integration
  - recvWindow validation according to Binance limits
  - Signature-ready query string construction

  For general parameter handling, delegates to ZenCex.Core.ParameterBuilder.
  All functions are pure with no side effects for reliable testing.
  """

  alias ZenCex.Core.ParameterBuilder, as: CoreParams
  alias ZenCex.Safety.ClockSync

  require Logger

  @type api_type :: :spot | :margin | :usdm_futures | :coinm_futures | :portfolio

  # Default recvWindow in milliseconds (Binance allows up to 60,000ms)
  @default_recv_window_ms 5000

  # Maximum allowed recvWindow per Binance documentation
  @max_recv_window_ms 60_000

  @doc """
  Builds query string with Binance-required parameter ordering.

  Binance API requires specific parameter order:
  1. Standard parameters (alphabetically sorted)
  2. timestamp
  3. recvWindow
  (signature is added separately by the Auth module)

  ## Parameters

    * `params` - Map of parameters to encode

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "timestamp" => "1234567890"}
      iex> ParameterBuilder.build_query_string(params)
      "symbol=BTCUSDT&timestamp=1234567890"

  ## Notes

  Parameter order is critical for Binance API signature validation.
  This function ensures consistent ordering that matches Binance expectations.
  Delegates standard query string construction to Core.ParameterBuilder.
  """
  @spec build_query_string(map()) :: String.t()
  def build_query_string(params) do
    # Split parameters into standard and timing groups
    grouped_params =
      CoreParams.split_params_by_groups(params,
        standard: Map.keys(params) -- ["timestamp", "recvWindow"],
        timing: ["timestamp", "recvWindow"]
      )

    # Build standard parameters query string (sorted)
    standard_query = CoreParams.build_query_string(grouped_params.standard)

    # Build timing parameters in Binance-specific order
    timing_query = build_timing_query_string(grouped_params.timing)

    # Combine with proper ordering
    case {standard_query, timing_query} do
      {"", ""} -> ""
      {"", timing} -> timing
      {standard, ""} -> standard
      {standard, timing} -> "#{standard}&#{timing}"
    end
  end

  @doc """
  Builds ordered query string for final authenticated URL construction.

  This function creates the final query string including signature parameter
  in the exact order required by Binance API.

  ## Parameters

    * `existing_params` - Non-timing parameters
    * `all_params` - All parameters including timing
    * `signature` - HMAC signature (must be last)

  ## Examples

      iex> existing = %{"symbol" => "BTCUSDT"}
      iex> all = %{"symbol" => "BTCUSDT", "timestamp" => "123", "recvWindow" => "5000"}
      iex> ParameterBuilder.build_ordered_query_string(existing, all, "abc123")
      "symbol=BTCUSDT&timestamp=123&recvWindow=5000&signature=abc123"
  """
  @spec build_ordered_query_string(map(), map(), String.t()) :: String.t()
  def build_ordered_query_string(existing_params, all_params, signature) do
    # Build standard params query string using Core module
    existing_query = CoreParams.build_query_string(existing_params)

    # Extract and build timing parameters
    timing_params = Map.take(all_params, ["timestamp", "recvWindow"])
    timing_query = build_required_timing_query_string(timing_params)

    # Combine all parts with signature last
    query_parts = Enum.reject([existing_query, timing_query, "signature=#{signature}"], &(&1 == ""))

    Enum.join(query_parts, "&")
  end

  @doc """
  Ensures timestamp and recvWindow parameters are present with valid values.

  Adds missing timing parameters and validates existing ones according to
  Binance API requirements.

  ## Parameters

    * `params` - Map of existing query parameters
    * `api_type` - Binance API type (for clock synchronization)

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT"}
      iex> result = ParameterBuilder.ensure_timing_params(params, :spot)
      iex> Map.has_key?(result, "timestamp")
      true
      iex> result["recvWindow"]
      "5000"
      iex> result["symbol"]
      "BTCUSDT"
  """
  @spec ensure_timing_params(map(), api_type(), keyword()) :: map()
  def ensure_timing_params(params, api_type, opts \\ []) do
    testnet = Keyword.get(opts, :testnet, false)

    params
    |> CoreParams.filter_optional_params()
    |> add_timestamp_if_missing(api_type, testnet)
    |> add_recv_window_if_missing()
    |> validate_timing_parameters()
  end

  # Private helper functions

  @spec build_timing_query_string(map()) :: String.t()
  defp build_timing_query_string(timing_params) do
    # Build timing parameters in specific Binance order: timestamp → recvWindow
    timing_parts = []

    timing_parts =
      if Map.has_key?(timing_params, "timestamp") do
        timing_parts ++ ["timestamp=#{timing_params["timestamp"]}"]
      else
        timing_parts
      end

    timing_parts =
      if Map.has_key?(timing_params, "recvWindow") do
        timing_parts ++ ["recvWindow=#{timing_params["recvWindow"]}"]
      else
        timing_parts
      end

    Enum.join(timing_parts, "&")
  end

  @spec build_required_timing_query_string(map()) :: String.t()
  defp build_required_timing_query_string(timing_params) do
    # Both timestamp and recvWindow are required in specific order
    Enum.join(["timestamp=#{timing_params["timestamp"]}", "recvWindow=#{timing_params["recvWindow"]}"], "&")
  end

  @spec add_timestamp_if_missing(map(), api_type(), boolean()) :: map()
  defp add_timestamp_if_missing(params, api_type, testnet) do
    if Map.has_key?(params, "timestamp") do
      params
    else
      timestamp = get_synchronized_timestamp(api_type, testnet)
      Map.put(params, "timestamp", timestamp)
    end
  end

  @spec add_recv_window_if_missing(map()) :: map()
  defp add_recv_window_if_missing(params) do
    if Map.has_key?(params, "recvWindow") do
      params
    else
      Map.put(params, "recvWindow", to_string(@default_recv_window_ms))
    end
  end

  @spec validate_timing_parameters(map()) :: map()
  defp validate_timing_parameters(params) do
    case Map.get(params, "recvWindow") do
      nil -> params
      recv_window_str -> validate_recv_window(params, recv_window_str)
    end
  end

  @spec validate_recv_window(map(), String.t()) :: map()
  defp validate_recv_window(params, recv_window_str) do
    case Integer.parse(recv_window_str) do
      {recv_window, ""} when recv_window > 0 and recv_window <= @max_recv_window_ms ->
        # Valid recvWindow, keep as-is
        params

      {recv_window, ""} when recv_window > @max_recv_window_ms ->
        # recvWindow too large, clamp to maximum
        Map.put(params, "recvWindow", to_string(@max_recv_window_ms))

      _invalid ->
        # Invalid recvWindow format, use default
        Map.put(params, "recvWindow", to_string(@default_recv_window_ms))
    end
  end

  @spec get_synchronized_timestamp(api_type(), boolean()) :: String.t()
  defp get_synchronized_timestamp(_api_type, testnet) do
    # Use Binance as the exchange identifier for ClockSync
    # All Binance API types use the same timing endpoint
    # Fallback to system time if ClockSync is not available (e.g., during tests)
    timestamp_ms =
      try do
        ClockSync.now_with_offset(:binance, testnet: testnet)
      rescue
        ArgumentError ->
          # ClockSync ETS table doesn't exist, fallback to system time
          System.system_time(:millisecond)
      end

    to_string(timestamp_ms)
  end
end
