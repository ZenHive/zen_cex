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

  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)
    prod_url = Keyword.fetch!(opts, :prod_url)
    test_url = Keyword.fetch!(opts, :test_url)

    # Generate the testnet environment variable name
    testnet_env_var = String.upcase("#{exchange}_testnet")

    quote do
      @exchange unquote(exchange)
      @prod_url unquote(prod_url)
      @test_url unquote(test_url)
      @testnet_env_var unquote(testnet_env_var)

      @doc """
      Returns the exchange name.
      """
      def __exchange__, do: @exchange

      @doc """
      Returns the current environment (prod or test).

      Checks #{unquote(testnet_env_var)} environment variable.
      """
      def current_env do
        determine_environment()
      end

      @doc """
      Returns the base URL for the current environment.
      """
      def base_url do
        case current_env() do
          :test -> @test_url
          :prod -> @prod_url
        end
      end

      @doc """
      Registry compatibility function.
      """
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
          nil -> :prod
          "false" -> :prod
          "" -> :prod
          _ -> :test
        end
      end

      # Allow adapters to override these if needed
      defoverridable current_env: 0, base_url: 0
    end
  end
end
