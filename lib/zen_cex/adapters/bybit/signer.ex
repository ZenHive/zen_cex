defmodule ZenCex.Adapters.Bybit.Signer do
  @moduledoc """
  Bybit-specific HMAC-SHA256 signature generation.

  This module handles Bybit's v5 API signature requirements, delegating
  the actual cryptographic operations to Core.Signer. It maintains Bybit's
  specific parameter concatenation and signature formatting requirements.

  ## Signature Process

  Bybit v5 API requires different signature formats for GET and POST:
  - GET: timestamp + api_key + recv_window + query_string
  - POST: timestamp + api_key + recv_window + json_body

  All functions are pure and deterministic for easy testing.
  """

  alias ZenCex.Adapters.Bybit.ParameterBuilder
  alias ZenCex.Core.Signer, as: CoreSigner

  @default_recv_window "5000"

  @doc """
  Creates HMAC-SHA256 signature for Bybit v5 API requests.

  Takes request parameters and generates the signature required by Bybit's
  authentication system. The signature format differs based on HTTP method.

  ## Parameters

    * `params` - Map of request parameters or JSON body string
    * `api_key` - The Bybit API key
    * `api_secret` - The Bybit API secret
    * `timestamp` - Request timestamp in milliseconds (as string)
    * `recv_window` - Receive window in milliseconds (default "5000")
    * `opts` - Options including:
      * `:method` - HTTP method (:get or :post), defaults to :get

  ## Examples

      # GET request signature
      iex> params = %{"symbol" => "BTCUSDT", "category" => "spot"}
      iex> Signer.create_signature(params, "api_key", "secret", "1658385579423")
      "a1b2c3..."  # 64-character lowercase hex string

      # POST request signature
      iex> json_body = ~s({"symbol":"BTCUSDT","category":"spot"})
      iex> Signer.create_signature(json_body, "api_key", "secret", "1658385579423", "5000", method: :post)
      "d4e5f6..."  # 64-character lowercase hex string

  ## Implementation Note

  For GET requests, params are converted to query string format.
  For POST requests, params should be provided as a JSON string.
  """
  @spec create_signature(map() | String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) :: String.t()
  def create_signature(params, api_key, api_secret, timestamp, recv_window \\ @default_recv_window, opts \\ []) do
    method = Keyword.get(opts, :method, :get)

    payload = build_signature_payload(params, api_key, timestamp, recv_window, method)
    sign_payload(payload, api_secret)
  end

  @doc """
  Signs a pre-built payload string with HMAC-SHA256.

  This is a pure function that performs the cryptographic signing operation.
  Useful for testing and when you already have a formatted payload string.

  ## Parameters

    * `payload` - The string to sign
    * `api_secret` - The secret key for HMAC signing

  ## Examples

      iex> Signer.sign_payload("1658385579423APIKEY5000symbol=BTCUSDT", "secret")
      "a1b2c3..."  # 64-character lowercase hex string

  ## Implementation Note

  Delegates to `ZenCex.Core.Signer.sign_payload/3` with Bybit-specific options:
  - `algorithm: :sha256` (Bybit uses SHA256)
  - `encoding: :hex` (returns hexadecimal string)
  - `case: :lower` (Bybit requires lowercase hex)
  """
  @spec sign_payload(String.t(), String.t()) :: String.t()
  def sign_payload(payload, api_secret) do
    # Bybit requires lowercase hex encoding for SHA256 signatures
    CoreSigner.sign_payload(payload, api_secret, algorithm: :sha256, encoding: :hex, case: :lower)
  end

  # Private implementation functions

  @spec build_signature_payload(map() | String.t(), String.t(), String.t(), String.t(), atom()) :: String.t()
  defp build_signature_payload(params, api_key, timestamp, recv_window, method) do
    case method do
      :get ->
        # GET: timestamp + api_key + recv_window + query_string
        query_string = build_query_string(params)
        "#{timestamp}#{api_key}#{recv_window}#{query_string}"

      :post ->
        # POST: timestamp + api_key + recv_window + json_body
        json_body = if is_binary(params), do: params, else: Jason.encode!(params)
        "#{timestamp}#{api_key}#{recv_window}#{json_body}"
    end
  end

  @spec build_query_string(map() | String.t()) :: String.t()
  defp build_query_string(params) when is_binary(params), do: params
  defp build_query_string(params) when params == %{}, do: ""

  defp build_query_string(params) do
    # Delegate to ParameterBuilder for consistent query string formatting
    ParameterBuilder.build_query_string(params)
  end
end
