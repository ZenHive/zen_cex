defmodule ZenCex.Core.Registry do
  @moduledoc """
  Registry for exchange adapters and their API modules.

  This module provides a central registry for mapping exchange names to their
  adapter namespaces. Each exchange has multiple API modules for different
  trading types (spot, futures, margin, etc.).

  ## Supported Exchanges

  Currently supported exchanges:
  - `:binance` - Binance exchange with Spot, Margin, Futures modules
  - `:bybit` - Bybit exchange with unified V5 API modules

  ## Examples

      # Get the registry module for an exchange
      iex> ZenCex.Core.Registry.get_registry!(:binance)
      ZenCex.Adapters.Binance.Endpoints

      # Get a specific API module
      iex> ZenCex.Core.Registry.get_module!(:binance, :spot)
      ZenCex.Adapters.Binance.Spot

      iex> ZenCex.Core.Registry.get_module!(:binance, :usdm_futures)
      ZenCex.Adapters.Binance.UsdmFutures

      iex> ZenCex.Core.Registry.list_exchanges()
      [:binance, :bybit]
  """

  @registries %{
    binance: ZenCex.Adapters.Binance.Endpoints,
    bybit: ZenCex.Adapters.Bybit.Endpoints
    # kraken: ZenCex.Adapters.Kraken.Endpoints,  # TODO: Implement Kraken
    # deribit: ZenCex.Adapters.Deribit.Endpoints  # TODO: Implement Deribit
  }

  # Validate at runtime on first access instead of compile time
  # This avoids circular dependency issues during compilation
  @spec ensure_module_loaded!(module(), atom()) :: :ok
  defp ensure_module_loaded!(module, name) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> raise "Module #{module} for #{name} failed to load: #{reason}"
    end
  end

  @doc """
  Gets the registry module for the specified exchange.

  The registry module provides discovery functions for exploring
  available API modules and endpoints.

  ## Parameters
  - `exchange` - Exchange atom (e.g., `:binance`, `:bybit`)

  ## Returns
  The registry module for the exchange.

  ## Raises
  - `RuntimeError` if the exchange is unknown or module fails to load

  ## Examples

      iex> ZenCex.Core.Registry.get_registry!(:binance)
      ZenCex.Adapters.Binance.Endpoints
  """
  @spec get_registry!(atom()) :: module()
  def get_registry!(exchange) do
    case @registries[exchange] do
      nil ->
        raise "Unknown exchange: #{exchange}"

      module ->
        ensure_module_loaded!(module, exchange)
        module
    end
  end

  @doc """
  Gets a specific API module for an exchange.

  ## Parameters
  - `exchange` - Exchange atom (e.g., `:binance`, `:bybit`)
  - `api_type` - API type atom (e.g., `:spot`, `:margin`, `:usdm_futures`)

  ## Returns
  The API module or raises if not found.

  ## Examples

      iex> ZenCex.Core.Registry.get_module!(:binance, :spot)
      ZenCex.Adapters.Binance.Spot

      iex> ZenCex.Core.Registry.get_module!(:binance, :usdm_futures)
      ZenCex.Adapters.Binance.UsdmFutures
  """
  @spec get_module!(atom(), atom()) :: module()
  def get_module!(exchange, api_type) do
    registry = get_registry!(exchange)

    case registry.get_module(api_type) do
      nil ->
        raise "Unknown API type #{api_type} for exchange #{exchange}"

      module ->
        ensure_module_loaded!(module, exchange)
        module
    end
  end

  @doc """
  Lists available API types for an exchange.

  ## Parameters
  - `exchange` - Exchange atom (e.g., `:binance`, `:bybit`)

  ## Returns
  List of API type atoms available for the exchange.

  ## Examples

      iex> ZenCex.Core.Registry.list_api_types(:binance)
      [:spot, :margin, :usdm_futures, :coinm_futures, :portfolio, :common, :market_data]
  """
  @spec list_api_types(atom()) :: [atom()]
  def list_api_types(exchange) do
    registry = get_registry!(exchange)
    registry.list_api_types()
  end

  @doc """
  Lists all supported exchange atoms.

  ## Returns
  List of exchange atoms that have registered adapters.

  ## Examples

      iex> ZenCex.Core.Registry.list_exchanges()
      [:binance, :bybit]
  """
  @spec list_exchanges() :: [atom()]
  def list_exchanges, do: Map.keys(@registries)
end
