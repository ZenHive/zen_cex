defmodule ZenCex.Adapters.CommonSigner do
  @moduledoc """
  Unified HMAC-SHA256 signer for all exchange adapters.

  Provides consistent signature generation across all CEX integrations
  using the Core.Signer module with standard HMAC-SHA256 options.

  ## Usage

  Exchange adapters can either use this module directly or delegate
  to it from their own Signer modules for backwards compatibility:

      defmodule ZenCex.Adapters.MyExchange.Signer do
        defdelegate sign_payload(payload, api_secret), 
          to: ZenCex.Adapters.CommonSigner
      end
  """

  alias ZenCex.Core.ParameterBuilder
  alias ZenCex.Core.Signer, as: CoreSigner

  @doc """
  Creates a signature from parameters using query string format.

  ## Parameters
    - `params` - Map of parameters to sign
    - `api_secret` - API secret key for signing

  ## Returns
    - HMAC-SHA256 signature as lowercase hex string
  """
  @spec create_signature(map(), String.t()) :: String.t()
  def create_signature(params, api_secret) do
    params
    |> ParameterBuilder.build_query_string()
    |> sign_payload(api_secret)
  end

  @doc """
  Creates a signature with custom payload format.

  ## Parameters
    - `payload` - Custom formatted payload string
    - `api_secret` - API secret key for signing

  ## Returns
    - HMAC-SHA256 signature as lowercase hex string
  """
  @spec create_signature_with_payload(String.t(), String.t()) :: String.t()
  def create_signature_with_payload(payload, api_secret) do
    sign_payload(payload, api_secret)
  end

  @doc """
  Signs a payload using HMAC-SHA256.

  ## Parameters
    - `payload` - String payload to sign
    - `api_secret` - API secret key for signing

  ## Returns
    - HMAC-SHA256 signature as lowercase hex string
  """
  @spec sign_payload(String.t(), String.t()) :: String.t()
  def sign_payload(payload, api_secret) do
    CoreSigner.sign_payload(payload, api_secret,
      algorithm: :sha256,
      encoding: :hex,
      case: :lower
    )
  end
end
