defmodule ZenCex.Adapters.Binance.Endpoints do
  @moduledoc """
  Declarative endpoint configuration for Binance REST API.

  Uses the EndpointRegistry macro to generate standard CRUD functions
  while allowing hand-written implementations for complex operations.

  ## Generated Functions

  The following functions are automatically generated from @endpoints:
  - `get_balances/1` - Fetch account balances
  - `get_positions/1` - Fetch futures positions
  - `place_order/1` - Place a new order
  - `cancel_order/1` - Cancel an existing order
  - `get_order/1` - Query order status
  - `get_open_orders/1` - List open orders
  - `get_ticker/1` - Get ticker price

  ## Complex Operations (Hand-written)

  - `place_oco_order/1` - One-Cancels-Other order
  - `batch_cancel_orders/1` - Cancel multiple orders
  """
  use ZenCex.EndpointRegistry, adapter: __MODULE__

  alias ZenCex.Adapters.Binance.{Parser, Auth, RateLimiter}

  # Define exchange identifier
  def __exchange__, do: :binance

  # Base URL configuration
  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"

  # Module references for Core.HTTP integration
  @doc "Returns the auth module for this exchange"
  def auth, do: ZenCex.Adapters.Binance.Auth

  @doc "Returns the rate limiter module for this exchange"
  def rate_limiter, do: ZenCex.Adapters.Binance.RateLimiter

  # Helper functions that need to be defined before @endpoints
  # These are public because they're referenced in @endpoints
  @doc false
  def transform_order_params(%{} = params) do
    # Ensure required fields and proper formatting
    params
    # Always get full response
    |> Map.put(:newOrderRespType, "FULL")
    |> Map.put(:timestamp, System.system_time(:millisecond))
    |> Map.put(:recvWindow, 5000)
  end

  @doc false
  def transform_oco_params(%{} = params) do
    params
    |> Map.put(:timestamp, System.system_time(:millisecond))
    |> Map.put(:recvWindow, 5000)
    |> Map.put(:newOrderRespType, "FULL")
  end

  @endpoints [
    # Account endpoints
    %{
      operation: :get_balances,
      method: :get,
      path: "/api/v3/account",
      requires_auth: true,
      response_parser: &Parser.parse_balances/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:rate_limited, :timeout],
      max_retries: 2,
      weight: 10,
      timeout: 10_000,
      doc: """
      Fetches current account balances.

      Returns a list of all assets with free and locked amounts.
      """
    },

    # Trading endpoints
    %{
      operation: :place_order,
      method: :post,
      path: "/api/v3/order",
      requires_auth: true,
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      # CRITICAL: Never retry order placement
      retry_on: [],
      max_retries: 0,
      weight: 1,
      timeout: 5_000,
      params_transformer: &__MODULE__.transform_order_params/1,
      doc: """
      Places a new order on the exchange.

      CRITICAL: This operation is never retried to prevent duplicate orders.

      ## Parameters
      - symbol: Trading pair (e.g., "BTCUSDT")
      - side: "BUY" or "SELL"
      - type: "LIMIT", "MARKET", etc.
      - quantity: Amount to trade
      - price: Limit price (for LIMIT orders)
      """
    },
    %{
      operation: :cancel_order,
      method: :delete,
      path: "/api/v3/order",
      requires_auth: true,
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:rate_limited],
      max_retries: 1,
      weight: 1,
      timeout: 5_000,
      doc: """
      Cancels an existing order.

      ## Parameters
      - symbol: Trading pair
      - orderId: Order ID to cancel (or origClientOrderId)
      """
    },
    %{
      operation: :get_order,
      method: :get,
      path: "/api/v3/order",
      requires_auth: true,
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:rate_limited, :timeout],
      max_retries: 3,
      weight: 2,
      timeout: 10_000,
      doc: """
      Queries the status of a specific order.

      ## Parameters
      - symbol: Trading pair
      - orderId: Order ID (or origClientOrderId)
      """
    },
    %{
      operation: :get_open_orders,
      method: :get,
      path: "/api/v3/openOrders",
      requires_auth: true,
      response_parser: &Parser.parse_orders_list/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:rate_limited, :timeout],
      max_retries: 2,
      weight: 3,
      timeout: 10_000,
      doc: """
      Lists all open orders.

      ## Parameters
      - symbol: (optional) Filter by trading pair
      """
    },

    # Futures endpoints
    %{
      operation: :get_positions,
      method: :get,
      path: "/fapi/v2/positionRisk",
      requires_auth: true,
      response_parser: &Parser.parse_positions/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:rate_limited, :timeout],
      max_retries: 3,
      weight: 5,
      timeout: 10_000,
      doc: """
      Fetches current futures positions.

      Returns all open positions with unrealized PnL.
      """
    },

    # Market data (public)
    %{
      operation: :get_ticker,
      method: :get,
      path: "/api/v3/ticker/price",
      requires_auth: false,
      response_parser: &Parser.parse_ticker/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:timeout],
      max_retries: 2,
      weight: 1,
      timeout: 5_000,
      doc: """
      Gets current ticker price for a symbol.

      ## Parameters
      - symbol: Trading pair (optional, returns all if not specified)
      """
    },

    # Time endpoint (for clock sync)
    %{
      operation: :get_server_time,
      method: :get,
      path: "/api/v3/time",
      requires_auth: false,
      response_parser: &Parser.parse_server_time/1,
      error_mapping: &Parser.parse_error/1,
      retry_on: [:timeout],
      max_retries: 2,
      weight: 1,
      timeout: 2_000,
      doc: """
      Gets the current server time.

      Used for clock synchronization.
      """
    }
  ]

  # Complex operations that need custom implementation

  @doc """
  Places a One-Cancels-Other (OCO) order.

  An OCO order combines a limit order and a stop-limit order.
  When one executes, the other is automatically cancelled.

  ## Parameters
  - symbol: Trading pair
  - side: "BUY" or "SELL"
  - quantity: Amount to trade
  - price: Limit price
  - stopPrice: Stop trigger price
  - stopLimitPrice: Limit price for stop order
  - api_key: (optional) Override API key from environment
  - api_secret: (optional) Override API secret from environment
  """
  @spec place_oco_order(map()) :: {:ok, map()} | {:error, term()}
  def place_oco_order(params) do
    # OCO orders have special handling and different response format
    # They also count as 2x weight for rate limiting

    # Extract credentials from params if provided, then remove them from the request body
    {credentials, clean_params} = extract_credentials(params)

    request =
      Req.new(
        method: :post,
        url: base_url(:prod) <> "/api/v3/order/oco",
        json: transform_oco_params(clean_params),
        receive_timeout: 5_000
      )
      |> Req.Request.register_options([:auth_credentials])
      |> maybe_add_credentials(credentials)
      |> Req.Request.prepend_request_steps(auth: &Auth.apply_auth/1)
      # OCO = 2x weight
      |> Req.Request.put_private(:rate_limit_weight, 2)
      |> Req.Request.put_private(:exchange, :binance)
      |> Req.Request.prepend_request_steps(rate_limit: &rate_limit_step/1)

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Parser.parse_oco_response(body)

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        Parser.parse_error(body)

      {:ok, response} ->
        {:error, response}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Cancels multiple orders in a single request.

  More efficient than individual cancellations for bulk operations.

  ## Parameters
  - symbol: Trading pair
  - order_ids: List of order IDs to cancel
  - api_key: (optional) Override API key from environment
  - api_secret: (optional) Override API secret from environment
  """
  @spec batch_cancel_orders(map()) :: {:ok, list()} | {:error, term()}
  def batch_cancel_orders(params) do
    # Extract required fields and credentials
    %{symbol: symbol, order_ids: order_ids} = params

    unless is_list(order_ids) do
      raise ArgumentError, "order_ids must be a list"
    end

    # Batch operations need special handling
    # Also has different weight calculation
    # Weight increases with batch size, max 10
    weight = min(length(order_ids), 10)

    # Extract credentials from params if provided
    {credentials, _clean_params} = extract_credentials(params)

    request =
      Req.new(
        method: :delete,
        url: base_url(:prod) <> "/api/v3/openOrders",
        json: %{
          symbol: symbol,
          orderIdList: Jason.encode!(order_ids)
        },
        receive_timeout: 10_000
      )
      |> Req.Request.register_options([:auth_credentials])
      |> maybe_add_credentials(credentials)
      |> Req.Request.prepend_request_steps(auth: &Auth.apply_auth/1)
      |> Req.Request.put_private(:rate_limit_weight, weight)
      |> Req.Request.put_private(:exchange, :binance)
      |> Req.Request.prepend_request_steps(rate_limit: &rate_limit_step/1)

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Parser.parse_batch_cancel_response(body)

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        Parser.parse_error(body)

      {:ok, response} ->
        {:error, response}

      {:error, _} = error ->
        error
    end
  end

  # Private helper functions

  @doc false
  @spec rate_limit_step(Req.Request.t()) :: Req.Request.t() | {Req.Request.t(), Req.Response.t()}
  defp rate_limit_step(request) do
    # Ensure rate limiter is initialized (idempotent operation)
    RateLimiter.init()

    # Extract endpoint from request URL
    endpoint =
      if request.url do
        request.url.path || "/"
      else
        "/"
      end

    # Get weight from private field
    weight = get_in(request.private, [:rate_limit_weight]) || 1

    # Check rate limit
    case RateLimiter.check_and_increment(endpoint, weight) do
      :ok ->
        request

      {:error, {:rate_limited, retry_after_ms}} ->
        # Return a response with retry-after header
        {request,
         %Req.Response{
           status: 429,
           body: "Rate limited",
           headers: [{"retry-after", Integer.to_string(div(retry_after_ms, 1000))}]
         }}
    end
  end

  # Credential handling helpers

  @doc false
  @spec extract_credentials(map()) :: {{String.t() | nil, String.t() | nil}, map()}
  defp extract_credentials(params) do
    api_key = Map.get(params, :api_key)
    api_secret = Map.get(params, :api_secret)

    clean_params =
      params
      |> Map.delete(:api_key)
      |> Map.delete(:api_secret)

    {{api_key, api_secret}, clean_params}
  end

  @doc false
  @spec maybe_add_credentials(Req.Request.t(), {String.t() | nil, String.t() | nil}) ::
          Req.Request.t()
  defp maybe_add_credentials(request, {nil, nil}) do
    # No credentials provided, Auth.apply_auth will use env vars
    request
  end

  defp maybe_add_credentials(request, {api_key, api_secret}) do
    # Add credentials to request options for Auth.apply_auth to use
    Req.merge(request,
      auth_credentials: %{
        api_key: api_key,
        api_secret: api_secret
      }
    )
  end
end
