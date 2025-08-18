defmodule ZenCex.Adapters.Binance.Endpoints do
  @moduledoc """
  Core endpoint configuration for Binance REST API.

  This module contains the essential endpoints that cover 80% of typical trading operations.
  Uses the EndpointRegistry macro to generate standard CRUD functions while allowing
  hand-written implementations for complex operations.

  ## Core vs Extended Endpoints

  This module includes only **core endpoints** that are essential for:
  - Account management (balances)
  - Order management (place, cancel, query)
  - Position tracking (spot and futures)
  - Trade history and execution reports
  - System utilities (server time)

  Extended endpoints (margin trading, savings, staking, etc.) will be implemented
  in separate feature modules under `endpoints/` when needed.

  ## API Types

  Each endpoint explicitly declares its `api_type` for clarity:
  - `:spot` - Spot trading endpoints (default)
  - `:futures` - USD-M Futures endpoints
  - `:sapi` - Wallet and account management (future)
  - `:coin_futures` - Coin-M Futures (future)

  ## ⚠️ CRITICAL: Environment Configuration

  **ALL endpoints respect the `BINANCE_TESTNET` environment variable:**
  - When `BINANCE_TESTNET=true`: Uses testnet URLs
  - Otherwise: Uses production URLs - **REAL MONEY**

  ### Check Current Environment

      iex> ZenCex.Adapters.Binance.Endpoints.current_env()
      :prod  # or :test
      
      iex> ZenCex.Adapters.Binance.Endpoints.base_url()
      "https://api.binance.com"  # or testnet URL

  ### Safety Guidelines
  - **Production is the default** - unset or any value except "true" uses production
  - **Use different API keys** for testnet vs production
  - **Verify environment before trading** - production uses real money!

  ## Core Functions (Generated)

  ### Account Management
  - `get_balances/1` - Fetch account balances (Spot)

  ### Order Management  
  - `place_order/1` - Place a new order ⚠️ **NEVER RETRIED**
  - `cancel_order/1` - Cancel an existing order
  - `get_order/1` - Query order status
  - `get_open_orders/1` - List open orders

  ### Position Tracking
  - `get_positions/1` - Fetch futures positions (Futures API)

  ### System
  - `get_server_time/1` - Get server timestamp (Public)

  ## Complex Operations (Hand-written)

  - `place_oco_order/1` - One-Cancels-Other order ⚠️ **NEVER RETRIED**
  - `batch_cancel_orders/1` - Cancel multiple orders (weight based on batch size)

  All functions above respect the `BINANCE_TESTNET` environment variable.
  """
  use ZenCex.EndpointRegistry, adapter: __MODULE__

  alias ZenCex.Adapters.Binance.{Auth, Parser, RateLimiter}

  # Configuration constants
  @default_recv_window 5000
  @max_batch_cancel_weight 10

  # Define exchange identifier
  def __exchange__, do: :binance

  # Base URL configuration
  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"

  @doc """
  Returns the current environment based on BINANCE_TESTNET environment variable.

  ## Returns
  - `:test` if `BINANCE_TESTNET=true` 
  - `:prod` otherwise (default)

  ## Examples
      
      iex> System.put_env("BINANCE_TESTNET", "true")
      iex> current_env()
      :test
      
      iex> System.delete_env("BINANCE_TESTNET")
      iex> current_env()
      :prod
      
  ## Safety Note
  Production is the default. Only exactly "true" enables testnet.
  Any other value (including "TRUE", "1", "yes") defaults to production.
  """
  @spec current_env() :: :prod | :test
  def current_env do
    case System.get_env("BINANCE_TESTNET") do
      "true" -> :test
      _ -> :prod
    end
  end

  @doc """
  Returns the base URL for the current environment.

  Automatically selects between production and testnet based on 
  the BINANCE_TESTNET environment variable.

  ## Examples

      iex> System.delete_env("BINANCE_TESTNET")
      iex> base_url()
      "https://api.binance.com"
      
      iex> System.put_env("BINANCE_TESTNET", "true")
      iex> base_url()
      "https://testnet.binance.vision"
      
  ## ⚠️ WARNING
  This function is used by ALL endpoints (both generated and hand-written).
  Changing the environment affects all API calls.
  """
  @spec base_url() :: String.t()
  def base_url do
    base_url(current_env())
  end

  @doc """
  Returns the auth module for this exchange.
  """
  @spec auth() :: module()
  def auth, do: Auth

  @doc """
  Returns the parser module for this exchange.
  """
  @spec parser() :: module()
  def parser, do: Parser

  @doc """
  Returns the rate limiter module for this exchange.
  """
  @spec rate_limiter() :: module()
  def rate_limiter, do: RateLimiter

  @doc """
  Returns the appropriate base URL for a specific API type.

  Binance has different base URLs for different product types:
  - Spot/Margin: api.binance.com / testnet.binance.vision
  - USD-M Futures: fapi.binance.com / testnet.binancefuture.com
  - Coin-M Futures: dapi.binance.com / testnet.binancefuture.com
  - Portfolio Margin: papi.binance.com / (no testnet yet)

  ## Examples

      iex> base_url(:prod, :spot)
      "https://api.binance.com"
      
      iex> base_url(:test, :futures)
      "https://testnet.binancefuture.com"
  """
  @spec base_url(atom(), atom()) :: String.t()
  def base_url(env, :spot), do: base_url(env)
  def base_url(:prod, :futures), do: "https://fapi.binance.com"
  def base_url(:test, :futures), do: "https://testnet.binancefuture.com"
  # TODO: Add coin_futures and portfolio when needed
  # def base_url(:prod, :coin_futures), do: "https://dapi.binance.com"
  # def base_url(:test, :coin_futures), do: "https://testnet.binancefuture.com"
  # def base_url(:prod, :portfolio), do: "https://papi.binance.com"

  # Module references for Core.HTTP integration (duplicates removed - defined above)

  # Helper functions that need to be defined before @endpoints
  # These are public because they're referenced in @endpoints
  @doc false
  def transform_order_params(%{} = params) do
    # Ensure required fields and proper formatting
    params
    # Always get full response
    |> Map.put(:newOrderRespType, "FULL")
    |> Map.put(:timestamp, System.system_time(:millisecond))
    |> Map.put(:recvWindow, @default_recv_window)
  end

  @doc false
  def transform_oco_params(%{} = params) do
    params
    |> Map.put(:timestamp, System.system_time(:millisecond))
    |> Map.put(:recvWindow, @default_recv_window)
    |> Map.put(:newOrderRespType, "FULL")
  end

  @endpoints [
    # Account endpoints
    %{
      operation: :get_balances,
      # Explicit for clarity
      api_type: :spot,
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
      # Spot trading endpoint
      api_type: :spot,
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
      # Spot trading endpoint
      api_type: :spot,
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
      # Spot trading endpoint
      api_type: :spot,
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
      # Spot trading endpoint
      api_type: :spot,
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
      # USD-M Futures API
      api_type: :futures,
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
      Fetches current futures positions from USD-M Futures API.

      Returns all open positions with unrealized PnL.
      """
    },

    # Time endpoint (for clock sync)
    %{
      operation: :get_server_time,
      # Available on all APIs, using spot for consistency
      api_type: :spot,
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

  **API Type**: `:spot` - OCO orders are only available for spot trading.

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
        url: base_url(current_env(), :spot) <> "/api/v3/order/oco",
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

  **API Type**: `:spot` - Batch cancellation for spot orders.

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
    # Weight increases with batch size
    weight = min(length(order_ids), @max_batch_cancel_weight)

    # Extract credentials from params if provided
    {credentials, _clean_params} = extract_credentials(params)

    request =
      Req.new(
        method: :delete,
        url: base_url(current_env(), :spot) <> "/api/v3/openOrders",
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
    # Extract endpoint from request URL
    endpoint =
      if request.url do
        request.url.path || "/"
      else
        "/"
      end

    # Get weight from private field
    weight = get_in(request.private, [:rate_limit_weight]) || 1

    # Check rate limit (always returns :ok in reactive mode)
    # We rely on Binance returning 429 and Req's retry mechanism
    :ok = RateLimiter.check_and_increment(endpoint, weight)
    request
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
