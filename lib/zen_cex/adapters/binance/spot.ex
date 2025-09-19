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

  alias ZenCex.Adapters.Binance.EndpointLoader
  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RequestHelper

  require EndpointLoader
  require Logger

  # Timeout for complex order operations (OCO, OTO, OTOCO) in milliseconds
  # 10 seconds allows for exchange processing of complex multi-leg orders
  # and network latency while preventing indefinite hangs
  @complex_order_timeout_ms 10_000

  # Load generated endpoints using the shared macro
  EndpointLoader.load_endpoints("generated_endpoints.ex", fn endpoint ->
    case endpoint.operation do
      # Fix balances operation name and parser
      :get_account ->
        %{endpoint | operation: :get_balances, response_parser: &Parser.parse_balances/1}

      # Fix account commission to use fees parser
      :"get_account/commission" ->
        %{endpoint | operation: :get_commission_rates, response_parser: &Parser.parse_fees/1}

      # Fix some operation names to be more intuitive
      :get_allOrders ->
        %{endpoint | operation: :get_order_history}

      :get_allOrderList ->
        %{endpoint | operation: :get_oco_history}

      :get_myTrades ->
        %{endpoint | operation: :get_trade_history}

      :delete_openOrders ->
        %{endpoint | operation: :cancel_all_orders}

      # Fix timeout for OCO operations (they're complex)
      op when op in [:"place_orderList/oco", :"place_orderList/oto", :"place_orderList/otoco"] ->
        # Never retry complex orders
        %{endpoint | timeout: @complex_order_timeout_ms, max_retries: 0, retry_on: []}

      _ ->
        endpoint
    end
  end)

  # The macro generates get_balances/1, place_order/1, cancel_order/1, get_order/1
  # along with their /2 variants and proper documentation

  @doc """
  Complex operation: Place One-Cancels-Other order.
  Hand-written because it requires special parameter handling.

  ## Parameters
  - `symbol` - Trading pair (e.g., "BTCUSDT")
  - `side` - Order side: "BUY" or "SELL"
  - `quantity` - Order quantity
  - `price` - Limit order price (for the take-profit order)
  - `stopPrice` - Stop trigger price
  - `stopLimitPrice` - Stop limit order execution price
  - `listClientOrderId` - (optional) Client order ID for the OCO order list
  - `limitClientOrderId` - (optional) Client order ID for the limit order
  - `stopClientOrderId` - (optional) Client order ID for the stop order

  ## Price Restrictions
  - SELL side: price > last price > stopPrice
  - BUY side: price < last price < stopPrice
  """
  @spec place_oco_order(map()) :: {:ok, map()} | {:error, term()}
  def place_oco_order(params) do
    # Validate required parameters
    with :ok <- validate_oco_params(params) do
      # Build OCO order parameters
      side = params[:side] || params["side"] || "SELL"

      base_params = %{
        "symbol" => params[:symbol] || params["symbol"],
        "side" => side,
        "quantity" => params[:quantity] || params["quantity"]
      }

      # Build side-specific parameters
      oco_params =
        base_params
        |> build_oco_params_for_side(side, params)
        |> add_optional_client_order_ids(params)

      # Execute the OCO order through the endpoint infrastructure
      # Note: Telemetry is handled automatically by Core.HTTP via Req/Finch
      config = build_oco_request_config()
      opts = []

      execute_endpoint_request(config, oco_params, opts, Endpoints)
    end
  end

  # Build OCO parameters based on order side
  defp build_oco_params_for_side(base_params, "SELL", params) do
    # SELL OCO: Above is take profit (LIMIT_MAKER), Below is stop loss (STOP_LOSS_LIMIT)
    # Price hierarchy: abovePrice (take profit) > current > belowPrice (stop loss)
    base_params
    |> Map.put("aboveType", "LIMIT_MAKER")
    |> Map.put("belowType", "STOP_LOSS_LIMIT")
    |> Map.put("abovePrice", params[:price] || params["price"] || params[:take_profit_price])
    |> Map.put("belowStopPrice", params[:stopPrice] || params["stopPrice"] || params[:stop_price])
    |> Map.put("belowPrice", params[:stopLimitPrice] || params["stopLimitPrice"] || params[:stop_limit_price])
    |> Map.put("belowTimeInForce", "GTC")
  end

  defp build_oco_params_for_side(base_params, "BUY", params) do
    # BUY OCO: Above is stop loss (STOP_LOSS_LIMIT), Below is take profit (LIMIT_MAKER)
    # Price hierarchy: abovePrice (stop loss) > current > belowPrice (take profit)
    base_params
    |> Map.put("aboveType", "STOP_LOSS_LIMIT")
    |> Map.put("belowType", "LIMIT_MAKER")
    |> Map.put("aboveStopPrice", params[:stopPrice] || params["stopPrice"] || params[:stop_price])
    |> Map.put("abovePrice", params[:stopLimitPrice] || params["stopLimitPrice"] || params[:stop_limit_price])
    |> Map.put("aboveTimeInForce", "GTC")
    |> Map.put("belowPrice", params[:price] || params["price"] || params[:take_profit_price])
  end

  defp build_oco_params_for_side(base_params, side, params) do
    # Default to SELL behavior for unknown sides (shouldn't happen with validation)
    Logger.warning("Unknown OCO order side: #{side}, defaulting to SELL")
    build_oco_params_for_side(base_params, "SELL", params)
  end

  # Add optional client order IDs if provided
  defp add_optional_client_order_ids(oco_params, params) do
    # Define parameter mappings to reduce complexity
    client_order_mappings = [
      {"listClientOrderId", [:listClientOrderId, "listClientOrderId", :list_client_order_id, "list_client_order_id"]},
      {"limitClientOrderId",
       [:limitClientOrderId, "limitClientOrderId", :limit_client_order_id, "limit_client_order_id"]},
      {"stopClientOrderId", [:stopClientOrderId, "stopClientOrderId", :stop_client_order_id, "stop_client_order_id"]}
    ]

    Enum.reduce(client_order_mappings, oco_params, fn {key, param_keys}, acc ->
      value = get_first_param_value(params, param_keys)
      maybe_add_param(acc, key, value)
    end)
  end

  # Extract first non-nil value from params using multiple possible keys
  defp get_first_param_value(params, keys) do
    Enum.find_value(keys, fn key -> params[key] end)
  end

  # Build request configuration for OCO orders
  defp build_oco_request_config do
    %{
      operation: :"place_orderList/oco",
      method: :post,
      path: "/api/v3/orderList/oco",
      requires_auth: true,
      weight: 1,
      timeout: @complex_order_timeout_ms,
      # Never retry complex orders to prevent duplicates
      max_retries: 0,
      retry_on: []
    }
  end

  defp maybe_add_param(map, _key, nil), do: map
  defp maybe_add_param(map, key, value), do: Map.put(map, key, value)

  defp validate_oco_params(params) do
    # Side is not required as it defaults to "SELL"
    required_keys = [:symbol, :quantity, :price, :stopPrice, :stopLimitPrice]

    missing_keys =
      Enum.filter(required_keys, fn key ->
        is_nil(params[key]) && is_nil(params[Atom.to_string(key)])
      end)

    if missing_keys == [] do
      :ok
    else
      {:error, {:missing_params, missing_keys}}
    end
  end

  @doc """
  Cancel an OCO (One-Cancels-Other) order list.

  ## Parameters
  - `symbol` - Trading pair (e.g., "BTCUSDT")
  - `orderListId` - Order list ID from the OCO order
  - `listClientOrderId` - (optional) Client order ID for the OCO order list
  - `newClientOrderId` - (optional) New client order ID for this cancellation request

  Either `orderListId` or `listClientOrderId` must be provided.
  """
  @spec cancel_oco_order(map()) :: {:ok, map()} | {:error, term()}
  def cancel_oco_order(params) do
    # Build cancel parameters using simplified parameter extraction
    cancel_params = build_cancel_oco_params(params)

    # Execute the cancellation through the endpoint infrastructure
    # Note: Telemetry is handled automatically by Core.HTTP via Req/Finch
    config = build_cancel_oco_request_config()
    opts = []

    execute_endpoint_request(config, cancel_params, opts, Endpoints)
  end

  # Build parameters for OCO cancellation
  defp build_cancel_oco_params(params) do
    # Define parameter mappings
    param_mappings = [
      {"symbol", [:symbol, "symbol"]},
      {"orderListId", [:orderListId, "orderListId", :order_list_id, "order_list_id"]},
      {"listClientOrderId", [:listClientOrderId, "listClientOrderId", :list_client_order_id, "list_client_order_id"]},
      {"newClientOrderId", [:newClientOrderId, "newClientOrderId", :new_client_order_id, "new_client_order_id"]}
    ]

    Enum.reduce(param_mappings, %{}, fn {key, param_keys}, acc ->
      value = get_first_param_value(params, param_keys)
      maybe_add_param(acc, key, value)
    end)
  end

  # Build request configuration for OCO cancellation
  defp build_cancel_oco_request_config do
    %{
      operation: :cancel_orderList,
      method: :delete,
      path: "/api/v3/orderList",
      requires_auth: true,
      weight: 1,
      timeout: 5000,
      max_retries: 1,
      retry_on: [:timeout]
    }
  end

  @doc """
  Get current price for a symbol from the market data API.

  This delegates to the MarketData module since ticker prices are public data
  and don't require authentication.

  ## Parameters
    - params: Map with :symbol key (e.g., %{symbol: "BTCUSDT"})

  ## Examples
      iex> Spot.get_ticker_price(%{symbol: "BTCUSDT"})
      {:ok, %{"symbol" => "BTCUSDT", "price" => "50000.00"}}
  """
  @spec get_ticker_price(map()) :: {:ok, map()} | {:error, term()}
  def get_ticker_price(params) do
    alias ZenCex.Adapters.Binance.MarketData

    MarketData.get_ticker_price(params)
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
    # Use the new high-level helper with Spot-specific logic
    RequestHelper.execute_request_for_api_type(
      config,
      params,
      opts,
      :spot,
      &RequestHelper.determine_spot_operation_type/1
    )
  end
end
