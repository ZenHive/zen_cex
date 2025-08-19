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

  require Logger

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
    require Logger
    # Get credentials from request options or environment
    api_key =
      get_in(request.options, [:auth_credentials, :api_key]) ||
        System.get_env("BINANCE_API_KEY")

    api_secret =
      get_in(request.options, [:auth_credentials, :api_secret]) ||
        System.get_env("BINANCE_API_SECRET")

    # TODO: Remove debug logging
    Logger.debug("Binance Auth: api_key present: #{api_key != nil}, api_secret present: #{api_secret != nil}")

    if api_key == nil do
      Logger.debug("Binance Auth: No API key found in options or env")
    end

    # Default to spot API type (could be made configurable via request.private)
    api_type = get_in(request.private, [:api_type]) || :spot

    if api_key && api_secret do
      Logger.debug("Binance Auth: Signing request with credentials")
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

    # TODO: Remove debug logging
    Logger.debug("Binance Auth: Starting to sign request for #{request.url}")

    # Add API key header
    request = Req.Request.put_header(request, "x-mbx-apikey", api_key)

    # Extract and merge params
    {all_params, has_json_option, body_params} = extract_request_params(request)

    # Ensure timing params are present
    all_params_with_timing = ensure_timing_params(all_params, api_type)

    # Generate signature for ALL params
    signature = generate_signature(all_params_with_timing, api_secret)

    # Build signed URL with proper parameter ordering
    final_url = build_signed_url(request.url, all_params_with_timing, signature)

    Logger.debug("Binance Auth: Final URL: #{final_url}")

    # Update request with signed URL and cleaned options
    updated_options = clean_request_options(request.options, has_json_option, body_params)

    %{request | url: URI.parse(final_url), options: updated_options}
  end

  # Extract params from request options
  # Returns {all_params, has_json_option, body_params}
  @spec extract_request_params(Req.Request.t()) :: {map(), boolean(), map()}
  defp extract_request_params(request) do
    has_json_option = Map.has_key?(request.options, :json)
    query_params = request.options[:params] || %{}
    body_params = request.options[:json] || %{}
    all_params = Map.merge(body_params, query_params)

    {all_params, has_json_option, body_params}
  end

  # Build the final URL with signed query string
  # Ensures proper parameter ordering as required by Binance API
  @spec build_signed_url(URI.t(), map(), String.t()) :: String.t()
  defp build_signed_url(url, params_with_timing, signature) do
    # Get existing query params (non-auth params like symbol, etc.)
    # Only drop the timing params, not signature (it's added separately)
    existing_params = Map.drop(params_with_timing, ["timestamp", "recvWindow"])

    # Build query string with proper ordering:
    # 1. Existing params first (alphabetically)
    # 2. timestamp
    # 3. recvWindow
    # 4. signature LAST
    query_string = build_ordered_query_string(existing_params, params_with_timing, signature)

    # Update the URL with the signed query string
    base_url = URI.to_string(%{url | query: nil})
    if query_string == "", do: base_url, else: "#{base_url}?#{query_string}"
  end

  # Build query string with Binance-required parameter ordering:
  # 1. Existing params (alphabetically)
  # 2. timestamp
  # 3. recvWindow  
  # 4. signature (MUST be last)
  @spec build_ordered_query_string(map(), map(), String.t()) :: String.t()
  defp build_ordered_query_string(existing_params, all_params, signature) do
    param_pairs = []

    # Add existing params (sorted for consistency)
    param_pairs =
      param_pairs ++
        (existing_params
         |> Enum.sort()
         |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end))

    # Add timing params
    param_pairs =
      param_pairs ++
        [
          "timestamp=#{all_params["timestamp"]}",
          "recvWindow=#{all_params["recvWindow"]}"
        ]

    # Add signature LAST
    param_pairs = param_pairs ++ ["signature=#{signature}"]

    Enum.join(param_pairs, "&")
  end

  # Clean request options after signing
  # Removes params (now in URL) and conditionally preserves json option
  @spec clean_request_options(map(), boolean(), map()) :: map()
  defp clean_request_options(options, has_json_option, body_params) do
    options
    # Always remove params - they're now in the URL
    |> Map.delete(:params)
    # Remove json first, then add back only if needed
    |> Map.delete(:json)
    |> then(fn opts ->
      # Only add json back if it was originally present AND has content
      if has_json_option and map_size(body_params) > 0 do
        Map.put(opts, :json, body_params)
      else
        opts
      end
    end)
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
    # Build query string with proper parameter ordering
    # Binance is sensitive to parameter order - cannot use URI.encode_query which sorts alphabetically
    query_string = build_query_string(params)

    # Generate HMAC-SHA256 signature
    :hmac
    |> :crypto.mac(:sha256, api_secret, query_string)
    |> Base.encode16(case: :lower)
  end

  # Private helper functions

  @spec build_query_string(map()) :: String.t()
  defp build_query_string(params) do
    # Build query string with Binance-expected parameter order
    # Important: Binance is sensitive to parameter order, cannot use URI.encode_query

    # Standard parameters (like symbol, side, quantity, etc.) come first (sorted)
    standard_params = Map.drop(params, ["timestamp", "recvWindow"])

    # Timing parameters come last in specific order
    timing_params = Map.take(params, ["timestamp", "recvWindow"])

    # Build param pairs maintaining proper order
    param_pairs = []

    # Add standard params (sorted for consistency)
    param_pairs =
      param_pairs ++
        (standard_params
         |> Enum.sort()
         |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end))

    # Add timing params in specific order
    param_pairs =
      if Map.has_key?(timing_params, "timestamp") do
        param_pairs ++ ["timestamp=#{timing_params["timestamp"]}"]
      else
        param_pairs
      end

    param_pairs =
      if Map.has_key?(timing_params, "recvWindow") do
        param_pairs ++ ["recvWindow=#{timing_params["recvWindow"]}"]
      else
        param_pairs
      end

    Enum.join(param_pairs, "&")
  end

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
