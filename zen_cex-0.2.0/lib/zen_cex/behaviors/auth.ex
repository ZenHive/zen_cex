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
    - opts: Additional options specific to the exchange. Can include:
      - `:api_key` - API key for authentication (falls back to env var)
      - `:api_secret` - API secret for signing (falls back to env var)
      - Exchange-specific options (e.g., `:timestamp`, `:recv_window` for Binance)

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

  ## Usage

      # Using options (preferred for testing)
      Auth.sign_request(request, api_key: "test_key", api_secret: "test_secret")

      # Using environment variables (for production)
      Auth.sign_request(request)
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
  Validates if the provided authentication credentials are valid.

  ## Parameters
    - opts: Keyword list or map with credentials:
      - `:api_key` - API key for authentication
      - `:api_secret` - API secret for signing

  ## Returns
    - `:ok` if credentials are valid
    - `{:error, reason}` if credentials are invalid or missing
  """
  @callback validate_credentials(keyword() | map()) :: :ok | {:error, term()}

  @doc """
  Returns the authentication method used by this exchange.

  ## Returns
    - `:hmac_sha256` - For HMAC-SHA256 (Binance)
    - `:hmac_sha512` - For HMAC-SHA512 (Kraken)
    - `:oauth2` - For OAuth2 (Deribit)
    - `:api_key` - For simple API key auth
  """
  @callback auth_method() :: :hmac_sha256 | :hmac_sha512 | :oauth2 | :api_key

  @optional_callbacks validate_credentials: 0, validate_credentials: 1
end
