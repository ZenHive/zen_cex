defmodule ZenCex.Adapters.Bybit.Auth do
  @moduledoc """
  Bybit authentication module implementing HMAC-SHA256 signing.

  Bybit v5 authentication requirements:
  - HMAC-SHA256 signature in X-BAPI-SIGN header
  - X-BAPI-API-KEY header with API key
  - X-BAPI-TIMESTAMP header with request timestamp
  - X-BAPI-RECV-WINDOW header with receive window (default 5000ms)
  - Signature format: timestamp + api_key + recv_window + query_string
  """

  use ZenCex.Adapters.BaseAuth, exchange: :bybit

  alias ZenCex.Adapters.Bybit.Signer
  alias ZenCex.Safety.ClockSync

  require Logger

  # Default receive window in milliseconds
  # 5 seconds
  @recv_window_default 5000

  @impl true
  def sign_request(request, api_key, api_secret, opts) do
    all_params = opts[:all_params] || %{}
    has_json_option = opts[:has_json_option] || false
    body_params = opts[:body_params] || %{}

    # TODO: Remove debug logging once authentication is stable
    Logger.debug("Bybit Auth: Starting to sign request", exchange: :bybit)

    # Add timing parameters using clock-synchronized time
    params_with_timing = ensure_timing_params(all_params)

    # Extract timestamp and recv_window for headers
    timestamp = Map.get(params_with_timing, "timestamp")
    recv_window = Map.get(params_with_timing, "recv_window", to_string(@recv_window_default))

    # Build query string for signature (params without timing)
    query_params = Map.drop(params_with_timing, ["timestamp", "recv_window"])

    # Determine HTTP method from request
    method = request.method || :get

    # Generate signature using Bybit format with correct method
    signature = Signer.create_signature(query_params, api_key, api_secret, timestamp, recv_window, method: method)

    # Apply authentication headers
    request
    |> add_auth_headers(api_key, timestamp, recv_window, signature)
    |> update_request_options(query_params, has_json_option, body_params)
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
    if ZenCex.Core.Auth.testnet?(:bybit) do
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
