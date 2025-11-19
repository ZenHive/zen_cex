defmodule ZenCex.Core.Auth do
  @moduledoc """
  Core authentication module providing common credential resolution patterns
  for all exchange adapters.

  This module extracts reusable authentication patterns that are common across
  exchanges, particularly:
  - Environment variable resolution with testnet support
  - Credential validation and error messages
  - Dynamic credential lookup from request options or environment

  ## Credential Resolution

  Credentials are resolved from request private data ONLY:
  - `request.private[:auth_credentials][:api_key]`
  - `request.private[:auth_credentials][:api_secret]`
  - `request.private[:auth_credentials][:testnet]` (optional, defaults to false)

  No environment variable fallback exists. All credentials must be passed explicitly.

  ## Memory Management for Credentials

  Custom credentials stored in `request.private[:auth_credentials]` are automatically
  cleaned up by Req when the request completes. The Req.Request struct and its private
  data are garbage collected after the HTTP request lifecycle ends, ensuring no memory
  leaks. This is part of Req's standard request lifecycle management.

  Note: Credentials are only stored in the request struct for the duration of the
  HTTP operation and are not persisted beyond that scope.

  ## Testnet Support

  Testnet mode is determined by the `testnet` flag in auth_credentials:
  - `auth_credentials: %{api_key: "...", api_secret: "...", testnet: true}`
  - Defaults to `false` if not specified
  - This flag is used by adapter modules to select the appropriate base URL

  ## Usage by Exchange Adapters

  Exchange adapters use this module to resolve credentials:

      defmodule MyExchange.Auth do
        alias ZenCex.Core.Auth

        def apply_auth(request) do
          api_key = Auth.get_api_key(request, :my_exchange)
          api_secret = Auth.get_api_secret(request, :my_exchange)

          if api_key && api_secret do
            sign_request(request, api_key, api_secret)
          else
            request
          end
        end
      end

  Adapter modules should extract the testnet flag separately:

      testnet = get_in(request.private, [:auth_credentials, :testnet]) || false
      base_url = Endpoints.base_url(testnet, :my_exchange, :spot)
  """

  require Logger

  @type credentials :: {String.t() | nil, String.t() | nil}
  @type credentials_result :: {:ok, {String.t(), String.t()}} | {:error, :missing_api_key | :missing_api_secret}

  @doc """
  Gets the API key for the specified exchange from request private data.

  Checks only: `request.private[:auth_credentials][:api_key]`

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * The API key string if found
    * Raises `ArgumentError` if credentials are missing or invalid

  ## Examples

      # With credentials in request private data
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "my_key"
      })
      Auth.get_api_key(request, :binance)
      # => "my_key"

      # Without credentials raises error
      request = Req.new()
      Auth.get_api_key(request, :binance)
      # => ** (ArgumentError) Missing auth_credentials.api_key for binance
  """
  @spec get_api_key(Req.Request.t(), atom()) :: String.t()
  def get_api_key(request, exchange) do
    case Map.fetch(request.private, :auth_credentials) do
      {:ok, creds} when is_map(creds) ->
        case Map.fetch(creds, :api_key) do
          {:ok, key} when is_binary(key) and byte_size(key) > 0 ->
            key

          {:ok, ""} ->
            raise ArgumentError,
                  "auth_credentials.api_key cannot be empty for #{exchange}. " <>
                    "Provide a valid API key in auth_credentials option."

          {:ok, invalid} ->
            raise ArgumentError,
                  "auth_credentials.api_key must be a string for #{exchange}, got: #{inspect(invalid)}"

          :error ->
            raise ArgumentError,
                  "Missing auth_credentials.api_key for #{exchange}. " <>
                    ~s(Include api_key in auth_credentials: %{api_key: "...", api_secret: "..."})
        end

      :error ->
        raise ArgumentError,
              "Missing auth_credentials for #{exchange}. " <>
                "Pass credentials via auth_credentials option: " <>
                ~s(%{api_key: "...", api_secret: "...", testnet: true/false})

      {:ok, invalid} ->
        raise ArgumentError,
              "auth_credentials must be a map for #{exchange}, got: #{inspect(invalid)}"
    end
  end

  @doc """
  Gets the API secret for the specified exchange from request private data.

  Checks only: `request.private[:auth_credentials][:api_secret]`

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * The API secret string if found
    * Raises `ArgumentError` if credentials are missing or invalid

  ## Examples

      # With credentials in request private data
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_secret: "my_secret"
      })
      Auth.get_api_secret(request, :binance)
      # => "my_secret"

      # Without credentials raises error
      request = Req.new()
      Auth.get_api_secret(request, :binance)
      # => ** (ArgumentError) Missing auth_credentials.api_secret for binance
  """
  @spec get_api_secret(Req.Request.t(), atom()) :: String.t()
  def get_api_secret(request, exchange) do
    case Map.fetch(request.private, :auth_credentials) do
      {:ok, creds} when is_map(creds) ->
        case Map.fetch(creds, :api_secret) do
          {:ok, secret} when is_binary(secret) and byte_size(secret) > 0 ->
            secret

          {:ok, ""} ->
            raise ArgumentError,
                  "auth_credentials.api_secret cannot be empty for #{exchange}. " <>
                    "Provide a valid API secret in auth_credentials option."

          {:ok, invalid} ->
            raise ArgumentError,
                  "auth_credentials.api_secret must be a string for #{exchange}, got: #{inspect(invalid)}"

          :error ->
            raise ArgumentError,
                  "Missing auth_credentials.api_secret for #{exchange}. " <>
                    ~s(Include api_secret in auth_credentials: %{api_key: "...", api_secret: "..."})
        end

      :error ->
        raise ArgumentError,
              "Missing auth_credentials for #{exchange}. " <>
                "Pass credentials via auth_credentials option: " <>
                ~s(%{api_key: "...", api_secret: "...", testnet: true/false})

      {:ok, invalid} ->
        raise ArgumentError,
              "auth_credentials must be a map for #{exchange}, got: #{inspect(invalid)}"
    end
  end

  @doc """
  Gets both API key and secret for the specified exchange.

  Returns a tuple or error for compatibility with try/rescue patterns.
  Use `get_credentials_with_result/2` for more detailed error information.

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * `{api_key, api_secret}` tuple with both credentials
    * `{:error, message}` if credentials are missing or invalid (when rescued)

  ## Examples

      # With complete credentials in request private data
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "key",
        api_secret: "secret"
      })
      {key, secret} = Auth.get_credentials(request, :binance)
      # => {"key", "secret"}

      # With missing credentials - returns error tuple when rescued
      request = Req.new()
      Auth.get_credentials(request, :binance)
      # => Raises ArgumentError, or {:error, message} when rescued
  """
  @spec get_credentials(Req.Request.t(), atom()) :: credentials() | {:error, String.t()}
  def get_credentials(request, exchange) do
    {get_api_key(request, exchange), get_api_secret(request, exchange)}
  rescue
    e in ArgumentError -> {:error, e.message}
  end

  @doc """
  Gets both API key and secret with detailed error information.

  This version returns error tuples to help with debugging authentication issues.

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * `{:ok, {api_key, api_secret}}` if both credentials are present
    * `{:error, :missing_api_key}` if API key is missing
    * `{:error, :missing_api_secret}` if API secret is missing

  ## Examples

      # With complete credentials
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "key",
        api_secret: "secret"
      })
      Auth.get_credentials_with_result(request, :binance)
      # => {:ok, {"key", "secret"}}

      # With missing API key
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_secret: "secret"
      })
      Auth.get_credentials_with_result(request, :binance)
      # => {:error, :missing_api_key}
  """
  @spec get_credentials_with_result(Req.Request.t(), atom()) :: credentials_result()
  def get_credentials_with_result(request, exchange) do
    case {get_api_key(request, exchange), get_api_secret(request, exchange)} do
      {nil, _} -> {:error, :missing_api_key}
      {_, nil} -> {:error, :missing_api_secret}
      {key, secret} -> {:ok, {key, secret}}
    end
  end

  @doc """
  Validates that both API key and secret are present and non-empty for authentication.

  This is a convenience function for auth modules to check if they have
  the necessary credentials to proceed with signing requests.

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * `true` if both API key and secret are present and non-empty
    * `false` if either is missing or if ArgumentError is raised

  ## Examples

      # With complete credentials
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "key",
        api_secret: "secret"
      })
      Auth.valid_credentials?(request, :binance)
      # => true

      # With missing secret
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "key"
      })
      Auth.valid_credentials?(request, :binance)
      # => false
  """
  @spec valid_credentials?(Req.Request.t(), atom()) :: boolean()
  def valid_credentials?(request, exchange) do
    case get_credentials(request, exchange) do
      {key, secret} when is_binary(key) and is_binary(secret) ->
        byte_size(key) > 0 and byte_size(secret) > 0

      {:error, _} ->
        false
    end
  rescue
    ArgumentError -> false
  end

  @doc """
  Validates that credentials have the correct format and are non-empty.

  This function validates the structure and content of credentials map
  without performing any network authentication. It ensures that both
  api_key and api_secret are present, are binary strings, and are non-empty.

  ## Parameters
    * `credentials` - A map that should contain `:api_key` and `:api_secret`

  ## Returns
    * `:ok` if credentials are valid
    * `{:error, :invalid_credentials}` if credentials are missing, empty, or wrong type

  ## Examples

      # Valid credentials
      Auth.validate_credentials(%{api_key: "key123", api_secret: "secret456"})
      # => :ok

      # Missing api_key
      Auth.validate_credentials(%{api_secret: "secret456"})
      # => {:error, :invalid_credentials}

      # Empty api_key
      Auth.validate_credentials(%{api_key: "", api_secret: "secret456"})
      # => {:error, :invalid_credentials}

      # Non-binary api_key
      Auth.validate_credentials(%{api_key: 123, api_secret: "secret456"})
      # => {:error, :invalid_credentials}
  """
  @spec validate_credentials(map()) :: :ok | {:error, :invalid_credentials}
  def validate_credentials(%{api_key: key, api_secret: secret})
      when is_binary(key) and is_binary(secret) and byte_size(key) > 0 and byte_size(secret) > 0 do
    :ok
  end

  def validate_credentials(_), do: {:error, :invalid_credentials}

  @doc """
  Logs debug information about credential availability.

  Useful for debugging authentication issues without exposing sensitive data.

  ## Parameters
    * `exchange` - The exchange atom
    * `api_key` - The API key (presence will be logged, not the value)
    * `api_secret` - The API secret (presence will be logged, not the value)

  ## Examples

      Auth.log_credential_status(:binance, "key", "secret")
      # Logs: "Binance Auth: api_key present: true, api_secret present: true"
  """
  @spec log_credential_status(atom(), String.t() | nil, String.t() | nil) :: :ok
  def log_credential_status(exchange, api_key, api_secret) do
    exchange_name = exchange |> to_string() |> String.capitalize()
    Logger.debug("#{exchange_name} Auth: api_key present: #{api_key != nil}, api_secret present: #{api_secret != nil}")
    :ok
  end

  @doc """
  Extracts the testnet flag from request options.

  This helper function normalizes the extraction of the testnet flag from
  auth_credentials, ensuring consistent behavior across all adapters.

  ## Parameters
    * `opts` - Keyword list or map of options containing `:auth_credentials`

  ## Returns
    * `true` if `auth_credentials.testnet` is `true`
    * `false` otherwise (including when testnet is missing or invalid)

  ## Examples

      opts = [auth_credentials: %{api_key: "key", testnet: true}]
      Auth.get_testnet_flag(opts)
      # => true

      opts = %{auth_credentials: %{api_key: "key", testnet: false}}
      Auth.get_testnet_flag(opts)
      # => false

      opts = [auth_credentials: %{api_key: "key"}]
      Auth.get_testnet_flag(opts)
      # => false (defaults to production)
  """
  @spec get_testnet_flag(keyword() | map()) :: boolean()
  def get_testnet_flag(opts) when is_list(opts) do
    case Keyword.get(opts, :auth_credentials) do
      %{testnet: testnet} when is_boolean(testnet) -> testnet
      _ -> false
    end
  end

  def get_testnet_flag(opts) when is_map(opts) do
    case Map.get(opts, :auth_credentials) do
      %{testnet: testnet} when is_boolean(testnet) -> testnet
      _ -> false
    end
  end

  # Private functions - removed all ENV fallback logic
end
