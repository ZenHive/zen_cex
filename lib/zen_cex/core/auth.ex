defmodule ZenCex.Core.Auth do
  @moduledoc """
  Core authentication module providing common credential resolution patterns
  for all exchange adapters.

  This module extracts reusable authentication patterns that are common across
  exchanges, particularly:
  - Environment variable resolution with testnet support
  - Credential validation and error messages
  - Dynamic credential lookup from request options or environment

  ## Credential Priority Order

  All exchanges follow the same credential resolution priority:

  1. **Request private data** (highest priority):
     - `request.private[:auth_credentials][:api_key]`
     - `request.private[:auth_credentials][:api_secret]`

  2. **Environment variables** (fallback):
     - When `{EXCHANGE}_TESTNET` is set: Uses testnet credentials
     - Otherwise: Uses production credentials

  ## Memory Management for Credentials

  Custom credentials stored in `request.private[:auth_credentials]` are automatically
  cleaned up by Req when the request completes. The Req.Request struct and its private
  data are garbage collected after the HTTP request lifecycle ends, ensuring no memory
  leaks. This is part of Req's standard request lifecycle management.

  Note: Credentials are only stored in the request struct for the duration of the
  HTTP operation and are not persisted beyond that scope.

  ## Testnet Support

  The module automatically detects testnet mode via environment variables:
  - `{EXCHANGE}_TESTNET` - If set to any value except "false" or "", enables testnet mode
  - `{EXCHANGE}_TESTNET_API_KEY` - Testnet API key (used when testnet mode is enabled)
  - `{EXCHANGE}_TESTNET_API_SECRET` - Testnet API secret (used when testnet mode is enabled)

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
  """

  require Logger

  @type credentials :: {String.t() | nil, String.t() | nil}
  @type credentials_result :: {:ok, {String.t(), String.t()}} | {:error, :missing_api_key | :missing_api_secret}

  # Values that disable testnet mode when set as EXCHANGE_TESTNET env var
  @testnet_disabled_values [nil, "", "false", "0", "no", "disabled"]

  @doc """
  Gets the API key for the specified exchange from request private data or environment.

  Checks in order:
  1. Request private data: `request.private[:auth_credentials][:api_key]`
  2. Environment variables based on testnet mode

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * The API key string if found
    * `nil` if no API key is available

  ## Examples

      # With credentials in request private data
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "my_key"
      })
      Auth.get_api_key(request, :binance)
      # => "my_key"

      # Falls back to environment variables when not in options
      # Assuming BINANCE_API_KEY="env_key" is set in environment
      request = Req.new()
      Auth.get_api_key(request, :binance)
      # => "env_key"
  """
  @spec get_api_key(Req.Request.t(), atom()) :: String.t() | nil
  def get_api_key(request, exchange) do
    # Use safer access pattern for better debugging
    case Map.fetch(request.private || %{}, :auth_credentials) do
      {:ok, creds} when is_map(creds) ->
        # If auth_credentials are explicitly provided, use them exclusively (no fallback)
        # Explicit validation to prevent silent failures
        case Map.fetch(creds, :api_key) do
          {:ok, key} when is_binary(key) and byte_size(key) > 0 -> key
          # Let caller handle missing or invalid key
          _ -> nil
        end

      _ ->
        get_api_key_from_env(exchange)
    end
  end

  @doc """
  Gets the API secret for the specified exchange from request private data or environment.

  Checks in order:
  1. Request private data: `request.private[:auth_credentials][:api_secret]`
  2. Environment variables based on testnet mode

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * The API secret string if found
    * `nil` if no API secret is available

  ## Examples

      # With credentials in request private data
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_secret: "my_secret"
      })
      Auth.get_api_secret(request, :binance)
      # => "my_secret"

      # Falls back to environment variables when not in options
      # Assuming BINANCE_API_SECRET="env_secret" is set in environment
      request = Req.new()
      Auth.get_api_secret(request, :binance)
      # => "env_secret"
  """
  @spec get_api_secret(Req.Request.t(), atom()) :: String.t() | nil
  def get_api_secret(request, exchange) do
    # Use safer access pattern for better debugging
    case Map.fetch(request.private || %{}, :auth_credentials) do
      {:ok, creds} when is_map(creds) ->
        # If auth_credentials are explicitly provided, use them exclusively (no fallback)
        # Explicit validation to prevent silent failures
        case Map.fetch(creds, :api_secret) do
          {:ok, secret} when is_binary(secret) and byte_size(secret) > 0 -> secret
          # Let caller handle missing or invalid secret
          _ -> nil
        end

      _ ->
        get_api_secret_from_env(exchange)
    end
  end

  @doc """
  Gets both API key and secret for the specified exchange.

  Returns the legacy tuple format for backward compatibility.
  Use `get_credentials_with_result/2` for more detailed error information.

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * `{api_key, api_secret}` tuple with both credentials
    * `{nil, nil}` if either credential is missing

  ## Examples

      # With complete credentials in request private data
      request = Req.new()
      |> Req.Request.put_private(:auth_credentials, %{
        api_key: "key",
        api_secret: "secret"
      })
      {key, secret} = Auth.get_credentials(request, :binance)
      # => {"key", "secret"}

      # With missing credentials
      request = Req.new()
      {key, secret} = Auth.get_credentials(request, :binance)
      # => {nil, nil}
  """
  @spec get_credentials(Req.Request.t(), atom()) :: credentials()
  def get_credentials(request, exchange) do
    case get_credentials_with_result(request, exchange) do
      {:ok, credentials} -> credentials
      {:error, _} -> {nil, nil}
    end
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
  Validates that both API key and secret are present for authentication.

  This is a convenience function for auth modules to check if they have
  the necessary credentials to proceed with signing requests.

  ## Parameters
    * `request` - The Req.Request struct containing options
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * `true` if both API key and secret are present
    * `false` if either is missing

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
      {nil, nil} -> false
      {_, _} -> true
    end
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
  Checks if the exchange is in testnet mode.

  An exchange is in testnet mode if the `{EXCHANGE}_TESTNET` environment
  variable is set to any value except "false" or "".

  ## Parameters
    * `exchange` - The exchange atom (e.g., `:binance`, `:bybit`, `:kraken`)

  ## Returns
    * `true` if testnet mode is enabled
    * `false` otherwise

  ## Examples

      # When BINANCE_TESTNET="true" is set in environment
      Auth.testnet?(:binance)
      # => true

      # When BINANCE_TESTNET is not set
      Auth.testnet?(:binance)
      # => false
  """
  @spec testnet?(atom()) :: boolean()
  def testnet?(exchange) do
    env_key = exchange_testnet_env_key(exchange)
    value = System.get_env(env_key)
    value not in @testnet_disabled_values
  end

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

  # Private functions

  @spec get_api_key_from_env(atom()) :: String.t() | nil
  defp get_api_key_from_env(exchange) do
    if testnet?(exchange) do
      # Try testnet key first, fall back to production
      testnet_key = System.get_env(exchange_testnet_api_key(exchange))
      production_key = System.get_env(exchange_api_key(exchange))
      testnet_key || production_key
    else
      System.get_env(exchange_api_key(exchange))
    end
  end

  @spec get_api_secret_from_env(atom()) :: String.t() | nil
  defp get_api_secret_from_env(exchange) do
    if testnet?(exchange) do
      # Try testnet secret first, fall back to production
      testnet_secret = System.get_env(exchange_testnet_api_secret(exchange))
      production_secret = System.get_env(exchange_api_secret(exchange))
      testnet_secret || production_secret
    else
      System.get_env(exchange_api_secret(exchange))
    end
  end

  # Environment variable name helpers

  @spec exchange_testnet_env_key(atom()) :: String.t()
  defp exchange_testnet_env_key(exchange) do
    "#{exchange |> to_string() |> String.upcase()}_TESTNET"
  end

  @spec exchange_api_key(atom()) :: String.t()
  defp exchange_api_key(exchange) do
    "#{exchange |> to_string() |> String.upcase()}_API_KEY"
  end

  @spec exchange_api_secret(atom()) :: String.t()
  defp exchange_api_secret(exchange) do
    "#{exchange |> to_string() |> String.upcase()}_API_SECRET"
  end

  @spec exchange_testnet_api_key(atom()) :: String.t()
  defp exchange_testnet_api_key(exchange) do
    "#{exchange |> to_string() |> String.upcase()}_TESTNET_API_KEY"
  end

  @spec exchange_testnet_api_secret(atom()) :: String.t()
  defp exchange_testnet_api_secret(exchange) do
    "#{exchange |> to_string() |> String.upcase()}_TESTNET_API_SECRET"
  end
end
