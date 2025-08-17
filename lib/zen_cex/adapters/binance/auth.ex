defmodule ZenCex.Adapters.Binance.Auth do
  @moduledoc """
  Binance authentication module implementing HMAC-SHA256 signing as a Req step.

  Supports all five Binance API types:
  - Spot & Cross Margin (api.binance.com)
  - USD-M Futures (fapi.binance.com)
  - COIN-M Futures (dapi.binance.com)
  - Portfolio Margin (papi.binance.com)

  Authentication is identical across all APIs:
  - HMAC-SHA256 signature as LAST query parameter
  - X-MBX-APIKEY header with API key
  - timestamp and optional recvWindow parameters
  - Automatic clock synchronization for accurate timestamps

  ## Clock Synchronization

  This module integrates with `ZenCex.Safety.ClockSync` to ensure accurate
  timestamps that account for clock drift between local system and Binance servers.
  This prevents authentication failures due to timestamp skew.
  """

  alias ZenCex.Safety.ClockSync

  @type api_type :: :spot | :margin | :usdm_futures | :coinm_futures | :portfolio

  # Default recvWindow in milliseconds (Binance allows up to 60,000ms)
  @default_recv_window_ms 5000
  # Maximum allowed recvWindow per Binance documentation
  @max_recv_window_ms 60_000

  @doc """
  Simplified auth function for use with endpoint registry and Core.HTTP.

  This function reads credentials from environment variables or request options
  and applies Binance authentication to the request.

  ## Parameters
    * `request` - The Req.Request struct to sign
    
  ## Returns
    * Modified request with Binance authentication applied
    
  ## Examples

      # Called by Core.HTTP auth_step
      request |> apply_auth()
  """
  @spec apply_auth(Req.Request.t()) :: Req.Request.t()
  def apply_auth(request) do
    # Get credentials from request options or environment
    api_key =
      get_in(request.options, [:auth_credentials, :api_key]) ||
        System.get_env("BINANCE_API_KEY")

    api_secret =
      get_in(request.options, [:auth_credentials, :api_secret]) ||
        System.get_env("BINANCE_API_SECRET")

    # Default to spot API type (could be made configurable via request.private)
    api_type = get_in(request.private, [:api_type]) || :spot

    if api_key && api_secret do
      sign_request(request, api_type, api_key, api_secret)
    else
      # Return request unchanged if no credentials available
      # Core.HTTP will handle the error appropriately
      request
    end
  end

  @doc """
  Signs a Req request with Binance HMAC-SHA256 authentication.

  This function works as a Req request step, adding:
  - X-MBX-APIKEY header
  - Clock-synchronized timestamp if not provided
  - Default recvWindow if not provided
  - HMAC-SHA256 signature as the LAST query parameter

  ## Parameters

    * `request` - The Req.Request struct to sign
    * `api_type` - The Binance API type (:spot, :margin, :usdm_futures, :coinm_futures, :portfolio)
    * `api_key` - The Binance API key
    * `api_secret` - The Binance API secret

  ## Examples

      iex> request = Req.new(url: "/api/v3/account")
      iex> signed = Auth.sign_request(request, :spot, "key", "secret")
      iex> Req.Request.get_header(signed, "x-mbx-apikey")
      ["key"]
  """
  @spec sign_request(Req.Request.t(), api_type(), String.t(), String.t()) :: Req.Request.t()
  def sign_request(request, api_type, api_key, api_secret) do
    # Validate API type
    _base_url = base_url(api_type)

    # Add API key header
    request = Req.Request.put_header(request, "x-mbx-apikey", api_key)

    # Get params and ensure timestamp/recvWindow are present
    params = request.options[:params] || %{}
    params_with_timing = ensure_timing_params(params, api_type)

    # Generate signature for params (without the signature field)
    signature = generate_signature(params_with_timing, api_secret)

    # Add signature to params
    # Note: Binance requires signature to be the last parameter in the actual HTTP request.
    # Req handles this by building the query string appropriately.
    updated_params = Map.put(params_with_timing, "signature", signature)

    %{request | options: Map.put(request.options, :params, updated_params)}
  end

  @doc """
  Ensures timestamp and recvWindow parameters are present with appropriate values.

  If timestamp is not provided, generates a clock-synchronized timestamp.
  If recvWindow is not provided, uses the default value.
  Validates recvWindow doesn't exceed Binance limits.

  ## Parameters

    * `params` - Map of existing query parameters
    * `api_type` - The Binance API type (used for exchange-specific clock sync)

  ## Examples

      params = %{"symbol" => "BTCUSDT"}
      enhanced = Auth.ensure_timing_params(params, :spot)
      # Returns map with timestamp and recvWindow added
  """
  @spec ensure_timing_params(map(), api_type()) :: map()
  def ensure_timing_params(params, api_type) do
    params
    |> ensure_timestamp(api_type)
    |> ensure_recv_window()
  end

  @doc """
  Generates HMAC-SHA256 signature for Binance API.

  ## Parameters

    * `params` - Map of query parameters (without signature)
    * `api_secret` - The Binance API secret

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "timestamp" => "1234567890"}
      iex> Auth.generate_signature(params, "secret")
      "..."  # 64-character hex string
  """
  @spec generate_signature(map(), String.t()) :: String.t()
  def generate_signature(params, api_secret) do
    # Convert params to query string maintaining order
    # Binance requires specific order (not sorted alphabetically)
    query_string = URI.encode_query(params)

    # Generate HMAC-SHA256 signature
    :crypto.mac(:hmac, :sha256, api_secret, query_string)
    |> Base.encode16(case: :lower)
  end

  # Private helper functions

  @spec ensure_timestamp(map(), api_type()) :: map()
  defp ensure_timestamp(params, api_type) do
    case Map.get(params, "timestamp") do
      nil ->
        # Generate clock-synchronized timestamp
        timestamp = get_synchronized_timestamp(api_type)
        Map.put(params, "timestamp", timestamp)

      _existing ->
        # Timestamp already provided, use as-is
        params
    end
  end

  @spec ensure_recv_window(map()) :: map()
  defp ensure_recv_window(params) do
    case Map.get(params, "recvWindow") do
      nil ->
        # Add default recvWindow
        Map.put(params, "recvWindow", to_string(@default_recv_window_ms))

      recv_window_str ->
        # Validate existing recvWindow
        validate_recv_window(params, recv_window_str)
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

  @doc """
  Returns the base URL for the given API type.

  ## Parameters

    * `api_type` - The Binance API type

  ## Examples

      iex> Auth.base_url(:spot)
      "https://api.binance.com"
      
      iex> Auth.base_url(:usdm_futures)
      "https://fapi.binance.com"
  """
  @spec base_url(api_type()) :: String.t()
  def base_url(:spot), do: "https://api.binance.com"
  def base_url(:margin), do: "https://api.binance.com"
  def base_url(:usdm_futures), do: "https://fapi.binance.com"
  def base_url(:coinm_futures), do: "https://dapi.binance.com"
  def base_url(:portfolio), do: "https://papi.binance.com"
end
