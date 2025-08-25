defmodule ZenCex.Adapters.Bybit.Auth do
  @moduledoc """
  Bybit authentication module implementing HMAC-SHA256 signing as a Req step.

  Bybit v5 uses a unified API where the same endpoints serve all product types
  (spot, derivatives, options) distinguished by a `category` parameter.

  Authentication requirements:
  - HMAC-SHA256 signature in X-BAPI-SIGN header
  - X-BAPI-API-KEY header with API key
  - X-BAPI-TIMESTAMP header with request timestamp
  - X-BAPI-RECV-WINDOW header with receive window (default 5000ms)
  - Signature format: timestamp + api_key + recv_window + query_string

  ## Architecture

  This module coordinates authentication by delegating to focused modules:
  - `Core.Auth` - Credential resolution from environment or request options
  - `Signer` - Pure HMAC-SHA256 signature generation
  - `ParameterBuilder` - Parameter handling and query string construction

  ## Clock Synchronization

  This module integrates with `ZenCex.Safety.ClockSync` to ensure accurate
  timestamps that account for clock drift between local system and Bybit servers.
  """
  alias ZenCex.Adapters.Bybit.Signer
  alias ZenCex.Core.Auth, as: CoreAuth
  alias ZenCex.Safety.ClockSync

  require Logger

  # Default receive window in milliseconds
  # 5 seconds
  @recv_window_default 5000

  @doc """
  Simplified auth function for use with endpoint registry and Core.HTTP.

  This function reads credentials from request options or environment variables
  and applies Bybit authentication to the request.

  ## Credential Priority Order

  1. **Request private data** (highest priority):
     - `request.private[:auth_credentials][:api_key]`
     - `request.private[:auth_credentials][:api_secret]`

  2. **Environment variables** (fallback):
     - When `BYBIT_TESTNET` is set: Uses `BYBIT_TESTNET_API_KEY` and `BYBIT_TESTNET_API_SECRET`
     - Otherwise: Uses `BYBIT_API_KEY` and `BYBIT_API_SECRET`

  ## Parameters
    * `request` - The Req.Request struct to sign

  ## Returns
    * Modified request with Bybit authentication applied (headers and signature)
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
  - `BYBIT_API_KEY` - Your Bybit API key
  - `BYBIT_API_SECRET` - Your Bybit API secret

  For testnet (when `BYBIT_TESTNET` is set to any value except "false" or ""):
  - `BYBIT_TESTNET_API_KEY` - Your Bybit testnet API key
  - `BYBIT_TESTNET_API_SECRET` - Your Bybit testnet API secret
  """
  @spec apply_auth(Req.Request.t()) :: Req.Request.t()
  def apply_auth(request) do
    # Check if we have valid credentials using Core.Auth helper
    if CoreAuth.valid_credentials?(request, :bybit) do
      # Get credentials and sign the request
      {api_key, api_secret} = CoreAuth.get_credentials(request, :bybit)

      # TODO: Remove debug logging once authentication is stable
      CoreAuth.log_credential_status(:bybit, api_key, api_secret)

      sign_request(request, api_key, api_secret)
    else
      # Return request unchanged if no credentials available
      # Core.HTTP will handle the error appropriately
      request
    end
  end

  @doc """
  Signs a Req request with Bybit HMAC-SHA256 authentication.

  This function works as a Req request step, adding:
  - X-BAPI-API-KEY header
  - X-BAPI-TIMESTAMP header with clock-synchronized timestamp
  - X-BAPI-RECV-WINDOW header with receive window
  - X-BAPI-SIGN header with HMAC-SHA256 signature

  ## Parameters

    * `request` - The Req.Request struct to sign
    * `api_key` - The Bybit API key
    * `api_secret` - The Bybit API secret

  ## Examples

      iex> request = Req.new(url: "/v5/account/wallet-balance")
      iex> signed = Auth.sign_request(request, "key", "secret")
      iex> Req.Request.get_header(signed, "x-bapi-api-key")
      ["key"]
  """
  @spec sign_request(Req.Request.t(), String.t(), String.t()) :: Req.Request.t()
  def sign_request(request, api_key, api_secret) do
    # TODO: Remove debug logging once authentication is stable
    Logger.debug("Bybit Auth: Starting to sign request", exchange: :bybit, url: request.url)

    # Extract parameters from request
    {all_params, has_json_option, body_params} = extract_request_params(request)

    # Add timing parameters using clock-synchronized time
    params_with_timing = ensure_timing_params(all_params)

    # Extract timestamp and recv_window for headers
    timestamp = Map.get(params_with_timing, "timestamp")
    recv_window = Map.get(params_with_timing, "recv_window", to_string(@recv_window_default))

    # Build query string for signature (params without timing)
    query_params = Map.drop(params_with_timing, ["timestamp", "recv_window"])

    # Generate signature using Bybit format
    signature = Signer.create_signature(query_params, api_key, api_secret, timestamp, recv_window)

    # Apply authentication headers
    request
    |> add_auth_headers(api_key, timestamp, recv_window, signature)
    |> update_request_options(query_params, has_json_option, body_params)
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

  # Ensures timestamp and recv_window parameters are present
  @spec ensure_timing_params(map()) :: map()
  defp ensure_timing_params(params) do
    params_with_timestamp =
      case Map.get(params, "timestamp") do
        nil ->
          # Get clock-synchronized timestamp for Bybit
          timestamp = ClockSync.now_with_offset(:bybit)
          Map.put(params, "timestamp", to_string(timestamp))

        _ ->
          params
      end

    # Add recv_window if not present
    Map.put_new(params_with_timestamp, "recv_window", to_string(@recv_window_default))
  end

  # Adds authentication headers to the request
  @spec add_auth_headers(Req.Request.t(), String.t(), String.t(), String.t(), String.t()) :: Req.Request.t()
  defp add_auth_headers(request, api_key, timestamp, recv_window, signature) do
    request
    |> Req.Request.put_header("x-bapi-api-key", api_key)
    |> Req.Request.put_header("x-bapi-timestamp", timestamp)
    |> Req.Request.put_header("x-bapi-recv-window", recv_window)
    |> Req.Request.put_header("x-bapi-sign", signature)
  end

  # Updates request options to use the signed parameters
  @spec update_request_options(Req.Request.t(), map(), boolean(), map()) :: Req.Request.t()
  defp update_request_options(request, query_params, has_json_option, body_params) do
    # For GET requests, params go in URL. For POST, they might go in body
    updated_options =
      request.options
      |> Map.put(:params, query_params)
      |> then(fn opts ->
        # Only preserve json option if it was originally present AND has content
        if has_json_option and map_size(body_params) > 0 do
          Map.put(opts, :json, body_params)
        else
          Map.delete(opts, :json)
        end
      end)

    %{request | options: updated_options}
  end

  @doc """
  Returns the base URL for Bybit based on testnet mode.

  ## Examples

      iex> Auth.base_url()
      "https://api.bybit.com"  # Production

      # When BYBIT_TESTNET is set
      iex> Auth.base_url()
      "https://api-testnet.bybit.com"  # Testnet
  """
  @spec base_url() :: String.t()
  def base_url do
    if CoreAuth.testnet?(:bybit) do
      "https://api-testnet.bybit.com"
    else
      "https://api.bybit.com"
    end
  end

  @doc """
  Generates HMAC-SHA256 signature for Bybit API.

  Public function for backward compatibility and testing.
  Delegates to the Signer module for signature generation.

  ## Parameters

    * `params` - Map of query parameters (without signature)
    * `api_key` - The Bybit API key
    * `api_secret` - The Bybit API secret
    * `timestamp` - Request timestamp in milliseconds
    * `recv_window` - Receive window in milliseconds (default 5000)

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "category" => "spot"}
      iex> Auth.generate_signature(params, "key", "secret", "1234567890", "5000")
      "..."  # 64-character hex string
  """
  @spec generate_signature(map(), String.t(), String.t(), String.t(), String.t()) :: String.t()
  def generate_signature(params, api_key, api_secret, timestamp, recv_window \\ to_string(@recv_window_default)) do
    Signer.create_signature(params, api_key, api_secret, timestamp, recv_window)
  end
end
