defmodule ZenCex.Examples.EndpointDiscovery do
  @moduledoc """
  Demonstrates endpoint introspection and discovery capabilities.

  ZenCex provides runtime discovery of available endpoints across all supported
  exchanges and API types. This enables:
  - Dynamic exploration of available operations
  - Programmatic validation of endpoint capabilities
  - Documentation generation
  - Development tooling support

  ## Related Documentation
  - README.md:409-426 - Endpoint discovery overview
  - `ZenCex.Adapters.Binance.Endpoints` - Registry and discovery module

  ## Examples

      alias ZenCex.Examples.EndpointDiscovery

      # List all available operations
      {:ok, endpoints} = EndpointDiscovery.list_all_endpoints()

      # Filter by API type
      {:ok, spot_ops} = EndpointDiscovery.list_spot_endpoints()
      {:ok, futures_ops} = EndpointDiscovery.list_futures_endpoints()

      # Get detailed endpoint information
      {:ok, info} = EndpointDiscovery.get_endpoint_details(:place_order, :spot)
  """

  alias ZenCex.Adapters.Binance.Endpoints

  @doc """
  Lists all available endpoint operations across all Binance API types.

  Returns a sorted, unique list of all operations available across spot, margin,
  futures, portfolio margin, and common endpoints.

  ## Returns
  - `{:ok, [atom()]}` - List of operation names (e.g., `:get_balances`, `:place_order`)

  ## Examples

      iex> {:ok, endpoints} = ZenCex.Examples.EndpointDiscovery.list_all_endpoints()
      iex> :get_balances in endpoints
      true
      iex> :place_order in endpoints
      true
      iex> is_list(endpoints)
      true
  """
  @spec list_all_endpoints() :: {:ok, [atom()]}
  def list_all_endpoints do
    endpoints = Endpoints.list_available_endpoints()
    {:ok, endpoints}
  end

  @doc """
  Lists all available endpoint operations for Spot trading API.

  Returns operations specific to Binance Spot trading, including account
  management, order placement, and trading operations.

  ## Returns
  - `{:ok, [atom()]}` - List of spot operation names

  ## Examples

      iex> {:ok, endpoints} = ZenCex.Examples.EndpointDiscovery.list_spot_endpoints()
      iex> :get_balances in endpoints
      true
      iex> :place_order in endpoints
      true
  """
  @spec list_spot_endpoints() :: {:ok, [atom()]}
  def list_spot_endpoints do
    endpoints = Endpoints.list_available_endpoints(:spot)
    {:ok, endpoints}
  end

  @doc """
  Lists all available endpoint operations for USD-M Futures trading API.

  Returns operations specific to Binance USD-M Futures (USDT-margined perpetuals
  and futures contracts).

  ## Returns
  - `{:ok, [atom()]}` - List of futures operation names

  ## Examples

      iex> {:ok, endpoints} = ZenCex.Examples.EndpointDiscovery.list_futures_endpoints()
      iex> :get_positions in endpoints
      true
      iex> :place_order in endpoints
      true
  """
  @spec list_futures_endpoints() :: {:ok, [atom()]}
  def list_futures_endpoints do
    endpoints = Endpoints.list_available_endpoints(:usdm_futures)
    {:ok, endpoints}
  end

  @doc """
  Returns detailed information about a specific endpoint operation.

  Provides comprehensive metadata about an endpoint including:
  - HTTP method and path
  - Authentication requirements
  - Rate limit weight
  - Timeout and retry configuration
  - Available function arities
  - Module location

  ## Parameters
  - `operation` - Operation name atom (e.g., `:get_balances`, `:place_order`)
  - `api_type` - API type atom (e.g., `:spot`, `:usdm_futures`, `:margin`)

  ## Returns
  - `{:ok, map()}` - Endpoint details including:
    - `:operation` - Operation name
    - `:method` - HTTP method (`:get`, `:post`, `:delete`)
    - `:path` - API path
    - `:requires_auth` - Authentication requirement (boolean)
    - `:weight` - Rate limit weight
    - `:api_type` - API type
    - `:module` - Implementing module
    - `:available_arities` - List of available function arities
  - `{:error, :not_found}` - Operation not found for specified API type

  ## Examples

      iex> {:ok, info} = ZenCex.Examples.EndpointDiscovery.get_endpoint_details(:get_balances, :spot)
      iex> info[:operation]
      :get_balances
      iex> info[:requires_auth]
      true
      iex> info[:api_type]
      :spot

      iex> {:ok, info} = ZenCex.Examples.EndpointDiscovery.get_endpoint_details(:place_order, :spot)
      iex> info[:method]
      :post
      iex> info[:requires_auth]
      true

      iex> ZenCex.Examples.EndpointDiscovery.get_endpoint_details(:nonexistent, :spot)
      {:error, :not_found}
  """
  @spec get_endpoint_details(atom(), atom()) :: {:ok, map()} | {:error, :not_found}
  def get_endpoint_details(operation, api_type) do
    case Endpoints.get_endpoint_info(operation, api_type) do
      nil -> {:error, :not_found}
      info -> {:ok, info}
    end
  end
end
