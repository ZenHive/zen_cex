defmodule ZenCex.Behaviors.Auth do
  @moduledoc """
  Behavior defining the authentication contract for exchange adapters.

  Each exchange has different authentication mechanisms (HMAC, OAuth, etc.)
  and this behavior provides a consistent interface for signing requests.
  """

  @doc """
  Signs a request with appropriate authentication credentials.

  ## Parameters
    - request: The Req request struct to sign
    - opts: Additional options specific to the exchange

  ## Returns
    - Modified request struct with authentication headers/params

  ## Examples

  For Binance (HMAC-SHA256):
    - Adds timestamp and signature to params
    - Adds X-MBX-APIKEY header

  For Kraken (HMAC-SHA512):
    - Adds nonce to body
    - Adds API-Key and API-Sign headers

  For Deribit (OAuth2):
    - Adds Bearer token to Authorization header
  """
  @callback sign_request(Req.Request.t(), keyword() | map()) :: Req.Request.t()

  @doc """
  Validates if the current authentication credentials are valid.

  ## Returns
    - `:ok` if credentials are valid
    - `{:error, reason}` if credentials are invalid or missing
  """
  @callback validate_credentials() :: :ok | {:error, term()}

  @doc """
  Returns the authentication method used by this adapter.

  ## Returns
    - `:hmac_sha256` - For HMAC-SHA256 (Binance)
    - `:hmac_sha512` - For HMAC-SHA512 (Kraken)
    - `:oauth2` - For OAuth2 (Deribit)
    - `:api_key` - For simple API key auth
  """
  @callback auth_method() :: :hmac_sha256 | :hmac_sha512 | :oauth2 | :api_key

  @optional_callbacks validate_credentials: 0
end
