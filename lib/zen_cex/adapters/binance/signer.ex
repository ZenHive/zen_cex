defmodule ZenCex.Adapters.Binance.Signer do
  @moduledoc """
  Binance-specific HMAC-SHA256 signature generation.

  This module handles Binance's specific signature requirements, delegating
  the actual cryptographic operations to Core.Signer. It maintains Binance's
  specific parameter ordering and signature formatting requirements.

  ## Signature Process

  1. Build query string from parameters with Binance-specific ordering
  2. Sign with HMAC-SHA256 (via Core.Signer)
  3. Return lowercase hexadecimal string

  All functions are pure and deterministic for easy testing.
  """

  alias ZenCex.Core.Signer, as: CoreSigner

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

  ## Implementation Note

  Delegates to `ZenCex.Core.Signer.sign_payload/3` with Binance-specific options:
  - `algorithm: :sha256` (Binance uses SHA256)
  - `encoding: :hex` (returns hexadecimal string)
  - `case: :lower` (Binance requires lowercase hex)

  See `ZenCex.Core.Signer` for other available algorithms and encoding options.
  """
  @spec sign_payload(String.t(), String.t()) :: String.t()
  def sign_payload(payload, api_secret) do
    # Binance requires lowercase hex encoding for SHA256 signatures
    CoreSigner.sign_payload(payload, api_secret, algorithm: :sha256, encoding: :hex, case: :lower)
  end

  # Private implementation functions

  @spec build_signature_payload(map()) :: String.t()
  defp build_signature_payload(params) do
    # Delegate to ParameterBuilder for Binance-specific query string construction
    # (handles parameter ordering and filtering requirements)
    ZenCex.Adapters.Binance.ParameterBuilder.build_query_string(params)
  end
end
