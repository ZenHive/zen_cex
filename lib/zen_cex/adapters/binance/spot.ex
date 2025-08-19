defmodule ZenCex.Adapters.Binance.Spot do
  @moduledoc """
  Spot trading endpoints for Binance.

  Contains all spot trading operations including:
  - Order management (place, cancel, query)
  - Account information (balances)
  - OCO orders
  - Batch operations
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints, debug: false

  alias ZenCex.Adapters.Binance.{Parser, RequestHelper}
  require Logger

  # Auth parameters that must be in query string
  @auth_params ["timestamp", "recvWindow", "signature"]

  @endpoints [
    %{
      operation: :get_balances,
      method: :get,
      path: "/api/v3/account",
      requires_auth: true,
      weight: 10,
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:rate_limited, :timeout],
      response_parser: &Parser.parse_balances/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get account balances.

      ## Error Scenarios

      - `{:error, {:unauthorized, "API-key format invalid."}}` - Invalid API key
      - `{:error, {:forbidden, "Timestamp for this request is outside of the recvWindow."}}` - Time sync issue
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },
    %{
      operation: :place_order,
      method: :post,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      timeout: 2_000,
      max_retries: 0,
      retry_on: [],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Place a new order.

      ## Error Scenarios

      - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
      - `{:error, {:insufficient_balance, "Account has insufficient balance"}}` - Not enough funds
      - `{:error, {:min_notional, "MIN_NOTIONAL not met"}}` - Order value too small
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },
    %{
      operation: :cancel_order,
      method: :delete,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      timeout: 2_000,
      max_retries: 1,
      retry_on: [:timeout],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Cancel an existing order.

      ## Error Scenarios

      - `{:error, {:unknown_order, "Order does not exist."}}` - Order not found
      - `{:error, {:order_filled, "Order already filled"}}` - Cannot cancel filled order
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },
    %{
      operation: :get_order,
      method: :get,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 2,
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get order details.

      ## Error Scenarios

      - `{:error, {:unknown_order, "Order does not exist."}}` - Order not found
      - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    }
  ]

  # The macro generates get_balances/1, place_order/1, cancel_order/1, get_order/1
  # along with their /2 variants and proper documentation

  @doc """
  Complex operation: Place One-Cancels-Other order.
  Hand-written because it requires special parameter handling.
  """
  @spec place_oco_order(map()) :: {:ok, map()} | {:error, term()}
  def place_oco_order(_params) do
    # TODO: Implement OCO order placement
    # This is a complex operation that places two orders where one cancels the other
    {:error, :not_implemented}
  end

  @doc """
  Complex operation: Batch cancel multiple orders.
  Hand-written because it requires special batch handling.
  """
  @spec batch_cancel_orders(map()) :: {:ok, list(map())} | {:error, term()}
  def batch_cancel_orders(_params) do
    # TODO: Implement batch cancellation
    # This cancels multiple orders in a single API call
    {:error, :not_implemented}
  end

  # The EndpointRegistry macro automatically generates:
  # - get_endpoint/1 
  # - all_endpoints/0
  # - get_weight/1
  # - Individual endpoint functions with proper specs and docs

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  # IMPORTANT: This must return {:ok, unparsed_body} or {:error, reason}
  # The EndpointRegistry macro will handle parsing the response
  defp execute_endpoint_request(config, params, opts, _adapter) do
    base_url =
      ZenCex.Adapters.Binance.Endpoints.base_url(
        ZenCex.Adapters.Binance.Endpoints.current_env(),
        :spot
      )

    # Determine operation type for Core.HTTP
    operation_type =
      cond do
        config.operation in [:place_order, :cancel_order] -> :trading
        config.operation == :get_order -> :standard
        true -> :standard
      end

    # Build request params based on method
    # For Binance, auth params (timestamp, recvWindow, signature) MUST be in query string
    request_params =
      case config.method do
        :get ->
          %{params: params}

        _ ->
          # For POST/PUT/DELETE, auth params go in query, body params in json
          # All endpoints in spot.ex have requires_auth: true
          auth_params = Map.take(params, @auth_params)
          body_params = Map.drop(params, @auth_params)
          %{params: auth_params, json: body_params}
      end

    # Use shared RequestHelper for consistency
    RequestHelper.execute_request(
      config,
      request_params,
      opts,
      base_url,
      :binance,
      operation_type
    )
  end
end
