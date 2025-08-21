defmodule ZenCex.Adapters.Binance.ParameterBuilder do
  @moduledoc """
  Parameter management and query string construction for Binance API requests.

  This module handles:
  - Binance-specific parameter ordering requirements
  - Timing parameter management (timestamp, recvWindow)
  - Query string construction with proper URL encoding
  - Parameter validation and defaults

  All functions are pure with no side effects for reliable testing.
  """

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
  """
  @spec build_query_string(map()) :: String.t()
  def build_query_string(params) do
    # Standard parameters (non-timing) come first, sorted alphabetically
    standard_params = Map.drop(params, ["timestamp", "recvWindow"])
    timing_params = Map.take(params, ["timestamp", "recvWindow"])

    param_pairs = []

    # Add standard params (sorted for consistency)
    param_pairs =
      param_pairs ++
        (standard_params
         |> Enum.sort()
         |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end))

    # Add timing params in specific order
    param_pairs = add_timing_to_pairs(param_pairs, timing_params)

    Enum.join(param_pairs, "&")
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
    param_pairs = []

    # Add existing params (sorted for consistency)
    param_pairs =
      param_pairs ++
        (existing_params
         |> Enum.sort()
         |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end))

    # Add timing params in required order
    param_pairs = add_required_timing_pairs(param_pairs, all_params)

    # Add signature LAST (critical requirement)
    param_pairs = param_pairs ++ ["signature=#{signature}"]

    Enum.join(param_pairs, "&")
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
      iex> ParameterBuilder.ensure_timing_params(params, :spot)
      %{"symbol" => "BTCUSDT", "timestamp" => "1234567890", "recvWindow" => "5000"}
  """
  @spec ensure_timing_params(map(), api_type()) :: map()
  def ensure_timing_params(params, api_type) do
    params
    |> add_timestamp_if_missing(api_type)
    |> add_recv_window_if_missing()
    |> validate_timing_parameters()
  end

  # Private helper functions

  @spec add_timing_to_pairs([String.t()], map()) :: [String.t()]
  defp add_timing_to_pairs(param_pairs, timing_params) do
    param_pairs =
      if Map.has_key?(timing_params, "timestamp") do
        param_pairs ++ ["timestamp=#{timing_params["timestamp"]}"]
      else
        param_pairs
      end

    if Map.has_key?(timing_params, "recvWindow") do
      param_pairs ++ ["recvWindow=#{timing_params["recvWindow"]}"]
    else
      param_pairs
    end
  end

  @spec add_required_timing_pairs([String.t()], map()) :: [String.t()]
  defp add_required_timing_pairs(param_pairs, all_params) do
    param_pairs ++
      [
        "timestamp=#{all_params["timestamp"]}",
        "recvWindow=#{all_params["recvWindow"]}"
      ]
  end

  @spec add_timestamp_if_missing(map(), api_type()) :: map()
  defp add_timestamp_if_missing(params, api_type) do
    if Map.has_key?(params, "timestamp") do
      params
    else
      timestamp = get_synchronized_timestamp(api_type)
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

  @spec get_synchronized_timestamp(api_type()) :: String.t()
  defp get_synchronized_timestamp(_api_type) do
    # Use Binance as the exchange identifier for ClockSync
    # All Binance API types use the same timing endpoint
    # Fallback to system time if ClockSync is not available (e.g., during tests)
    timestamp_ms =
      try do
        ClockSync.now_with_offset(:binance)
      rescue
        ArgumentError ->
          # ClockSync ETS table doesn't exist, fallback to system time
          System.system_time(:millisecond)
      end

    to_string(timestamp_ms)
  end
end
