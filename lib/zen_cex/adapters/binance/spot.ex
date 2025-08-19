defmodule ZenCex.Adapters.Binance.Spot do
  @moduledoc """
  Spot trading endpoints for Binance.

  Contains all spot trading operations including:
  - Order management (place, cancel, query)
  - Account information (balances)
  - OCO orders
  - Batch operations
  """

  alias ZenCex.Adapters.Binance.{Parser, RequestHelper}
  require Logger

  @endpoints_config %{
    get_balances: %{
      operation: :get_balances,
      method: :get,
      path: "/api/v3/account",
      requires_auth: true,
      weight: 10,
      # 5 second timeout for account query
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:rate_limited, :timeout],
      response_parser: &Parser.parse_balances/1,
      error_mapping: &Parser.parse_error/1
    },
    place_order: %{
      operation: :place_order,
      method: :post,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      # 2 second timeout for trading
      timeout: 2_000,
      # CRITICAL: No retries for order placement
      max_retries: 0,
      # Never retry order placement
      retry_on: [],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    },
    cancel_order: %{
      operation: :cancel_order,
      method: :delete,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      # 2 second timeout for cancellation
      timeout: 2_000,
      # Limited retries for cancellation
      max_retries: 1,
      # Only retry on timeout, not rate limit
      retry_on: [:timeout],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    },
    get_order: %{
      operation: :get_order,
      method: :get,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 2,
      # 5 second timeout for query
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    }
  }

  @doc """
  Get account balances.
  
  ## Error Scenarios
  
  - `{:error, {:unauthorized, "API-key format invalid."}}` - Invalid API key
  - `{:error, {:forbidden, "Timestamp for this request is outside of the recvWindow."}}` - Time sync issue
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  """
  @spec get_balances(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_balances(params \\ %{}, opts \\ []) do
    execute_request(:get_balances, params, opts)
  end

  @doc """
  Place a new order.
  
  ## Error Scenarios
  
  - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
  - `{:error, {:insufficient_balance, "Account has insufficient balance"}}` - Not enough funds
  - `{:error, {:min_notional, "MIN_NOTIONAL not met"}}` - Order value too small
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  """
  @spec place_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_order(params \\ %{}, opts \\ []) do
    execute_request(:place_order, params, opts)
  end

  @doc """
  Cancel an existing order.
  
  ## Error Scenarios
  
  - `{:error, {:unknown_order, "Order does not exist."}}` - Order not found
  - `{:error, {:order_filled, "Order already filled"}}` - Cannot cancel filled order
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  """
  @spec cancel_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def cancel_order(params \\ %{}, opts \\ []) do
    execute_request(:cancel_order, params, opts)
  end

  @doc """
  Get order details.
  
  ## Error Scenarios
  
  - `{:error, {:unknown_order, "Order does not exist."}}` - Order not found
  - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  """
  @spec get_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_order(params \\ %{}, opts \\ []) do
    execute_request(:get_order, params, opts)
  end

  @doc """
  Complex operation: Place One-Cancels-Other order.
  Hand-written because it requires special parameter handling.
  """
  def place_oco_order(_params) do
    # TODO: Implement OCO order placement
    # This is a complex operation that places two orders where one cancels the other
    {:error, :not_implemented}
  end

  @doc """
  Complex operation: Batch cancel multiple orders.
  Hand-written because it requires special batch handling.
  """
  def batch_cancel_orders(_params) do
    # TODO: Implement batch cancellation
    # This cancels multiple orders in a single API call
    {:error, :not_implemented}
  end

  @doc """
  Returns the endpoint configuration for the given operation.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(operation) do
    Map.get(@endpoints_config, operation)
  end

  @doc """
  Returns all endpoints defined in this module.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints do
    Map.values(@endpoints_config)
  end

  # Private helper to execute requests
  defp execute_request(operation, params, opts) do
    config = Map.get(@endpoints_config, operation)

    base_url =
      ZenCex.Adapters.Binance.Endpoints.base_url(
        ZenCex.Adapters.Binance.Endpoints.current_env(),
        :spot
      )

    # Determine operation type for Core.HTTP
    operation_type =
      cond do
        operation in [:place_order, :cancel_order] -> :trading
        operation == :get_order -> :standard
        true -> :standard
      end

    RequestHelper.execute_request(config, params, opts, base_url, :binance, operation_type)
  end
end
