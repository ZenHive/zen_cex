defmodule ZenCex.Adapters.Binance.Signer do
  @moduledoc """
  Binance-specific signature generation.

  Delegates to CommonSigner for HMAC-SHA256 operations while maintaining
  backwards compatibility with existing Binance adapter code.
  """

  alias ZenCex.Adapters.CommonSigner

  @doc """
  Creates HMAC-SHA256 signature for Binance API request parameters.

  ## Parameters
    * `params` - Map of request parameters (already includes timing)
    * `api_secret` - The Binance API secret key

  ## Returns
    * 64-character lowercase hex string signature
  """
  @spec create_signature(map(), String.t()) :: String.t()
  def create_signature(params, api_secret) do
    params
    |> ZenCex.Adapters.Binance.ParameterBuilder.build_query_string()
    |> CommonSigner.sign_payload(api_secret)
  end

  @doc """
  Signs a payload string with HMAC-SHA256.
  Delegates to CommonSigner for consistency across adapters.
  """
  @spec sign_payload(String.t(), String.t()) :: String.t()
  defdelegate sign_payload(payload, api_secret), to: CommonSigner
end
