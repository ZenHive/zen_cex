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

  ## Architecture

  This module coordinates authentication by delegating to focused modules:
  - `Signer` - Pure HMAC-SHA256 signature generation
  - `ParameterBuilder` - Parameter ordering and timing management

  ## Clock Synchronization

  This module integrates with `ZenCex.Safety.ClockSync` to ensure accurate
  timestamps that account for clock drift between local system and Binance servers.
  This prevents authentication failures due to timestamp skew.
  """
  alias ZenCex.Adapters.Binance.ParameterBuilder
  alias ZenCex.Adapters.Binance.Signer
  alias ZenCex.Core.Auth, as: CoreAuth

  require Logger

  @type api_type :: :spot | :margin | :usdm_futures | :coinm_futures | :portfolio

  @doc """
  Simplified auth function for use with endpoint registry and Core.HTTP.

  This function reads credentials from request options or environment variables
  and applies Binance authentication to the request.

  ## Credential Priority Order

  1. **Request private data** (highest priority):
     - `request.private[:auth_credentials][:api_key]`
     - `request.private[:auth_credentials][:api_secret]`

  2. **Environment variables** (fallback):
     - When `BINANCE_TESTNET` is set: Uses `BINANCE_TESTNET_API_KEY` and `BINANCE_TESTNET_API_SECRET`
     - Otherwise: Uses `BINANCE_API_KEY` and `BINANCE_API_SECRET`

  ## Parameters
    * `request` - The Req.Request struct to sign

  ## Returns
    * Modified request with Binance authentication applied (headers and signature)
    * Returns request unchanged if no credentials are available

  ## Examples

      # Using environment variables (automatic)
      request |> apply_auth()

      # Passing credentials via request private data (for multi-tenant apps)
      request
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "user_specific_key",
        api_secret: "user_specific_secret"
      })
      |> apply_auth()

  ## Environment Variables

  For production:
  - `BINANCE_API_KEY` - Your Binance API key
  - `BINANCE_API_SECRET` - Your Binance API secret

  For testnet (when `BINANCE_TESTNET` is set to any value except "false" or ""):
  - `BINANCE_TESTNET_API_KEY` - Your Binance testnet API key
  - `BINANCE_TESTNET_API_SECRET` - Your Binance testnet API secret
  """
  @spec apply_auth(Req.Request.t()) :: Req.Request.t()
  def apply_auth(request) do
    # Check if we have valid credentials using Core.Auth helper
    if CoreAuth.valid_credentials?(request, :binance) do
      # Get credentials and sign the request
      {api_key, api_secret} = CoreAuth.get_credentials(request, :binance)

      # TODO: Remove debug logging once authentication is stable
      CoreAuth.log_credential_status(:binance, api_key, api_secret)

      # Default to spot API type (could be made configurable via request.private)
      api_type = get_in(request.private, [:api_type]) || :spot

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

    # TODO: Remove debug logging once authentication is stable
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

    # Add timing parameters (delegate to ParameterBuilder)
    params_with_timing = ParameterBuilder.ensure_timing_params(all_params, api_type)

    # Generate signature (delegate to Signer)
    signature = Signer.create_signature(params_with_timing, api_secret)

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
    # Get existing query params (non-timing params like symbol, etc.)
    existing_params = Map.drop(params_with_timing, ["timestamp", "recvWindow"])

    # Build query string with proper ordering (delegate to ParameterBuilder)
    query_string = ParameterBuilder.build_ordered_query_string(existing_params, params_with_timing, signature)

    # Update the URL with the signed query string
    base_url = URI.to_string(%{url | query: nil})
    if query_string == "", do: base_url, else: "#{base_url}?#{query_string}"
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
    ParameterBuilder.ensure_timing_params(params, api_type)
  end

  @doc """
  Generates HMAC-SHA256 signature for Binance API.

  Public function for backward compatibility and testing.
  Delegates to the Signer module for signature generation.

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
    Signer.create_signature(params, api_secret)
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
