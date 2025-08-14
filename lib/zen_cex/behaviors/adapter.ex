defmodule ZenCex.Behaviors.Adapter do
  @moduledoc """
  Behavior defining the contract for exchange adapters.

  Each exchange adapter must implement these callbacks to provide
  a consistent interface for the core system.
  """

  @doc """
  Returns the base URL for the exchange API.

  ## Parameters
    - environment: `:prod` or `:test`

  ## Returns
    - String containing the base URL
  """
  @callback base_url(atom()) :: String.t()

  @doc """
  Fetches positions from the exchange.

  ## Parameters
    - params: Map containing request parameters

  ## Returns
    - `{:ok, list()}` - List of positions
    - `{:error, term()}` - Error reason
  """
  @callback get_positions(map()) :: {:ok, list()} | {:error, term()}

  @doc """
  Fetches account balances from the exchange.

  ## Parameters
    - params: Map containing request parameters

  ## Returns
    - `{:ok, list()}` - List of balances
    - `{:error, term()}` - Error reason
  """
  @callback get_balances(map()) :: {:ok, list()} | {:error, term()}

  @doc """
  Places an order on the exchange.

  ## Parameters
    - symbol: Trading pair symbol
    - side: `:buy` or `:sell`
    - type: Order type (e.g., `:market`, `:limit`)
    - params: Additional order parameters

  ## Returns
    - `{:ok, map()}` - Order details
    - `{:error, term()}` - Error reason
  """
  @callback place_order(String.t(), atom(), atom(), map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Cancels an existing order.

  ## Parameters
    - order_id: The order identifier
    - params: Additional parameters

  ## Returns
    - `{:ok, map()}` - Cancellation details
    - `{:error, term()}` - Error reason
  """
  @callback cancel_order(String.t(), map()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks place_order: 4, cancel_order: 2
end
