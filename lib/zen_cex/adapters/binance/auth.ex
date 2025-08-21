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

    request
    |> prepare_authentication(api_key)
    |> apply_signature(api_type, api_secret)
  end

  # Prepares the request with authentication headers
  @spec prepare_authentication(Req.Request.t(), String.t()) :: Req.Request.t()
  defp prepare_authentication(request, api_key) do
    add_auth_headers(request, api_key)
  end

  # Applies timing parameters and signature to the request
  @spec apply_signature(Req.Request.t(), api_type(), String.t()) :: Req.Request.t()
  defp apply_signature(request, api_type, api_secret) do
    # Extract parameters from request
    {all_params, has_json_option, body_params} = extract_request_params(request)

    # Add timing parameters
    params_with_timing = ensure_timing_params(all_params, api_type)

    # Generate signature
    signature = create_hmac_signature(params_with_timing, api_secret)

    # Build final authenticated request
    build_authenticated_request(
      request,
      params_with_timing,
      signature,
      has_json_option,
      body_params
    )
  end

  # Adds authentication headers to the request
  @spec add_auth_headers(Req.Request.t(), String.t()) :: Req.Request.t()
  defp add_auth_headers(request, api_key) do
    Req.Request.put_header(request, "x-mbx-apikey", api_key)
  end

  # Creates HMAC-SHA256 signature for the request parameters
  @spec create_hmac_signature(map(), String.t()) :: String.t()
  defp create_hmac_signature(params, api_secret) do
    payload = build_signature_payload(params)
    sign_payload(payload, api_secret)
  end

  # Signs a payload with HMAC-SHA256
  @spec sign_payload(String.t(), String.t()) :: String.t()
  defp sign_payload(payload, api_secret) do
    payload
    |> compute_hmac_sha256(api_secret)
    |> encode_signature()
  end

  # Builds the final authenticated request with signed URL
  @spec build_authenticated_request(
          Req.Request.t(),
          map(),
          String.t(),
          boolean(),
          map()
        ) :: Req.Request.t()
  defp build_authenticated_request(request, params_with_timing, signature, has_json_option, body_params) do
    request
    |> update_request_url(params_with_timing, signature)
    |> update_request_options(has_json_option, body_params)
  end

  # Updates the request URL with signed parameters
  @spec update_request_url(Req.Request.t(), map(), String.t()) :: Req.Request.t()
  defp update_request_url(request, params_with_timing, signature) do
    final_url = build_signed_url(request.url, params_with_timing, signature)
    Logger.debug("Binance Auth: Final URL: #{final_url}")
    %{request | url: URI.parse(final_url)}
  end

  # Updates the request options after signing
  @spec update_request_options(Req.Request.t(), boolean(), map()) :: Req.Request.t()
  defp update_request_options(request, has_json_option, body_params) do
    updated_options = clean_request_options(request.options, has_json_option, body_params)
    %{request | options: updated_options}
  end

  @spec build_signature_payload(map()) :: String.t()
  defp build_signature_payload(params) do
    build_query_string(params)
  end

  @spec compute_hmac_sha256(String.t(), String.t()) :: binary()
  defp compute_hmac_sha256(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
  end

  @spec encode_signature(binary()) :: String.t()
  defp encode_signature(raw_signature) do
    Base.encode16(raw_signature, case: :lower)
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
    |> add_timestamp_if_missing(api_type)
    |> add_recv_window_if_missing()
    |> validate_timing_parameters()
  end

  # Adds timestamp if not present
  @spec add_timestamp_if_missing(map(), api_type()) :: map()
  defp add_timestamp_if_missing(params, api_type) do
    if Map.has_key?(params, "timestamp") do
      params
    else
      timestamp = get_synchronized_timestamp(api_type)
      Map.put(params, "timestamp", timestamp)
    end
  end

  # Adds default recvWindow if not present
  @spec add_recv_window_if_missing(map()) :: map()
  defp add_recv_window_if_missing(params) do
    if Map.has_key?(params, "recvWindow") do
      params
    else
      Map.put(params, "recvWindow", to_string(@default_recv_window_ms))
    end
  end

  # Validates timing parameters are within acceptable bounds
  @spec validate_timing_parameters(map()) :: map()
  defp validate_timing_parameters(params) do
    case Map.get(params, "recvWindow") do
      nil -> params
      recv_window_str -> validate_recv_window(params, recv_window_str)
    end
  end

  @doc """
  Generates HMAC-SHA256 signature for Binance API.

  Public function for backward compatibility and testing.
  Internally delegates to the refactored signature creation.

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
    create_hmac_signature(params, api_secret)
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
