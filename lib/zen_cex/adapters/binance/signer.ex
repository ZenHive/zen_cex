defmodule ZenCex.Adapters.Binance.Signer do
  @moduledoc """
  Pure HMAC-SHA256 signature generation for Binance API authentication.

  This module contains the cryptographic operations needed for Binance API
  signatures. It is a focused module that handles only signature generation,
  with no side effects or external dependencies.

  ## Signature Process

  1. Build query string from parameters (delegated to ParameterBuilder)
  2. Compute HMAC-SHA256 hash using API secret
  3. Encode result as lowercase hexadecimal string

  All functions are pure and deterministic for easy testing.
  """

  @doc """
  Creates HMAC-SHA256 signature for Binance API request parameters.

  Takes a map of parameters and API secret, returns the signature string
  required by Binance API authentication.

  ## Parameters

    * `params` - Map of request parameters (already includes timing)
    * `api_secret` - The Binance API secret key

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "timestamp" => "1234567890"}
      iex> Signer.create_signature(params, "secret_key")
      "a1b2c3..."  # 64-character lowercase hex string

  ## Notes

  The parameter map should already include timing parameters (timestamp, recvWindow)
  as this module focuses purely on the cryptographic signature generation.
  """
  @spec create_signature(map(), String.t()) :: String.t()
  def create_signature(params, api_secret) do
    params
    |> build_signature_payload()
    |> sign_payload(api_secret)
  end

  @doc """
  Signs a payload string with HMAC-SHA256 using the provided secret.

  This is a pure function that performs the cryptographic signing operation.
  Useful for testing and when you already have a formatted payload string.

  ## Parameters

    * `payload` - The string to sign (usually a query string)
    * `api_secret` - The secret key for HMAC signing

  ## Examples

      iex> Signer.sign_payload("symbol=BTCUSDT&timestamp=1234567890", "secret")
      "a1b2c3..."  # 64-character lowercase hex string
  """
  @spec sign_payload(String.t(), String.t()) :: String.t()
  def sign_payload(payload, api_secret) do
    payload
    |> compute_hmac_sha256(api_secret)
    |> encode_signature()
  end

  # Private implementation functions

  @spec build_signature_payload(map()) :: String.t()
  defp build_signature_payload(params) do
    # Delegate to ParameterBuilder for consistent query string construction
    ZenCex.Adapters.Binance.ParameterBuilder.build_query_string(params)
  end

  @spec compute_hmac_sha256(String.t(), String.t()) :: binary()
  defp compute_hmac_sha256(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
  end

  @spec encode_signature(binary()) :: String.t()
  defp encode_signature(raw_signature) do
    Base.encode16(raw_signature, case: :lower)
  end
end
