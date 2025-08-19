defmodule ZenCex.Adapters.Binance.Spot do
  @moduledoc """
  Spot trading endpoints for Binance.

  Contains all spot trading operations including:
  - Order management (place, cancel, query)
  - Account information (balances)
  - OCO orders
  - Batch operations
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Core.HTTP
  require Logger

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

    # Build request using Core.HTTP patterns
    # Important: We need to return the RAW response for the macro to parse
    api_type = Map.get(config, :api_type, :spot)

    # Build request params based on method
    request_params =
      case config.method do
        :get ->
          %{params: params}

        _ ->
          if config.requires_auth do
            # For authenticated requests, separate auth params from body params
            auth_params = Map.take(params, ["timestamp", "recvWindow", "signature"])
            body_params = Map.drop(params, ["timestamp", "recvWindow", "signature"])
            %{params: auth_params, json: body_params}
          else
            %{params: nil, json: params}
          end
      end

    # Build base options - DON'T add empty params or json
    base_opts = %{
      method: config.method,
      url: base_url <> config.path,
      receive_timeout: Keyword.get(opts, :timeout, config.timeout),
      skip_auth: not config.requires_auth,
      retry: false
    }

    # Only add params if they exist and are not empty
    base_opts =
      if Map.has_key?(request_params, :params) and request_params.params != nil and
           request_params.params != %{} do
        Map.put(base_opts, :params, request_params.params)
      else
        base_opts
      end

    # Only add json if it exists and is not empty
    base_opts =
      if Map.has_key?(request_params, :json) and request_params.json != nil and
           request_params.json != %{} do
        Map.put(base_opts, :json, request_params.json)
      else
        base_opts
      end

    request =
      HTTP.base_request(:binance, operation_type)
      |> Req.merge(Map.to_list(base_opts))
      |> Req.merge(opts)
      |> Req.Request.put_private(:rate_limit_weight, config.weight)
      |> Req.Request.put_private(:endpoint_config, config)
      |> Req.Request.put_private(:endpoint_operation, config.operation)
      |> Req.Request.put_private(:api_type, api_type)

    # Execute request and return RAW body for the macro to parse
    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        # Return the RAW body - the macro will call the parser
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        # Return error response for the macro to map
        {:error, %Req.Response{status: status, body: body}}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, exception}
    end
  end
end
