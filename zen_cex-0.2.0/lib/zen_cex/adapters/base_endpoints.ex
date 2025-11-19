defmodule ZenCex.Adapters.BaseEndpoints do
  @moduledoc """
  Common endpoint adapter patterns for all exchanges.

  This module provides shared functionality for exchange endpoint modules including:
  - Environment detection (prod/test) with persistent_term caching
  - Base URL resolution based on environment
  - Standard exchange metadata functions
  - Registry compatibility functions

  ## Usage

      defmodule MyExchange.Endpoints do
        use ZenCex.Adapters.BaseEndpoints,
          exchange: :my_exchange,
          prod_url: "https://api.myexchange.com",
          test_url: "https://testnet.myexchange.com"
      end
  """

  @doc """
  Makes a module use the BaseEndpoints behavior.

  ## Options
  - `:exchange` - The exchange atom (required)
  - `:prod_url` - Production API URL (required)
  - `:test_url` - Testnet/sandbox API URL (required)
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)
    prod_url = Keyword.fetch!(opts, :prod_url)
    test_url = Keyword.fetch!(opts, :test_url)

    # Generate the testnet environment variable name
    testnet_env_var = String.upcase("#{exchange}_testnet")

    quote do
      require Logger

      @exchange unquote(exchange)
      @prod_url unquote(prod_url)
      @test_url unquote(test_url)
      @testnet_env_var unquote(testnet_env_var)

      @doc """
      Returns the exchange name.
      """
      @spec __exchange__() :: atom()
      def __exchange__, do: @exchange

      @doc """
      Returns the current environment (prod or test).

      Checks #{unquote(testnet_env_var)} environment variable.
      The value is cached using :persistent_term for performance.

      ## Caching Behavior
      - Environment is determined once per application start and cached
      - Cache persists until the application restarts (not cleared by code reloads)
      - During development, restart the application if you change environment variables
      - To force cache refresh in IEx: `:persistent_term.erase({__MODULE__, :current_env})`

      ## Override
      Adapters may override this to support additional environments or
      different detection logic (e.g., multiple test environments).
      """
      @spec current_env() :: :prod | :test
      def current_env do
        # Use persistent_term for efficient caching across processes
        # Include app name to avoid collisions
        key = {:zen_cex, __MODULE__, :current_env}

        case :persistent_term.get(key, :not_cached) do
          :not_cached ->
            # Determine environment once
            env = determine_environment()
            # Use put which is atomic - worst case multiple processes set the same value
            # This is safe because determine_environment() is deterministic
            :persistent_term.put(key, env)
            env

          cached_env ->
            cached_env
        end
      end

      @doc """
      Returns the base URL for the current environment.

      ## Override
      Adapters may override this to support API-type specific URLs
      (e.g., different URLs for spot vs futures trading).
      """
      @spec base_url() :: String.t()
      def base_url do
        case current_env() do
          :test -> @test_url
          :prod -> @prod_url
        end
      end

      @doc """
      Registry compatibility function.
      Returns metadata about this exchange adapter.
      """
      @spec info() :: map()
      def info do
        %{
          exchange: @exchange,
          module: __MODULE__,
          auth: auth(),
          rate_limiter: rate_limiter(),
          parser: parser()
        }
      end

      # Private functions

      defp determine_environment do
        case System.get_env(@testnet_env_var) do
          nil ->
            Logger.debug("No #{@testnet_env_var} set, defaulting to production")
            :prod

          "false" ->
            Logger.debug("#{@testnet_env_var}='false', using production")
            :prod

          "FALSE" ->
            Logger.debug("#{@testnet_env_var}='FALSE', using production")
            :prod

          "0" ->
            Logger.debug("#{@testnet_env_var}='0', using production")
            :prod

          "" ->
            Logger.debug("#{@testnet_env_var} is empty, using production")
            :prod

          "true" ->
            Logger.debug("#{@testnet_env_var}='true', using testnet")
            :test

          "TRUE" ->
            Logger.debug("#{@testnet_env_var}='TRUE', using testnet")
            :test

          "1" ->
            Logger.debug("#{@testnet_env_var}='1', using testnet")
            :test

          value ->
            # Fail fast with clear error for unexpected values
            raise ArgumentError, """
            Invalid value for #{@testnet_env_var}: #{inspect(value)}

            Expected one of:
            - Production: nil, "", "false", "FALSE", "0"
            - Testnet: "true", "TRUE", "1"

            This prevents accidental usage of production APIs when testnet was expected.
            """
        end
      end

      # Allow adapters to override these if needed
      defoverridable current_env: 0, base_url: 0
    end
  end
end
