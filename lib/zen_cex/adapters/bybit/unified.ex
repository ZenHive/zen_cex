defmodule ZenCex.Adapters.Bybit.Unified do
  @moduledoc """
  Unified trading endpoints for Bybit v5 API.

  This module provides access to all Bybit v5 unified trading endpoints which
  serve spot, linear (USDT perpetual), inverse (coin perpetual), and options
  trading through a single API distinguished by the `category` parameter.

  ## Category Values

  - `"spot"` - Spot trading
  - `"linear"` - USDT-margined perpetual futures
  - `"inverse"` - Coin-margined perpetual futures
  - `"option"` - Options trading

  ## Usage

  Direct calls with category parameter:
      Unified.place_order(%{category: "spot", symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      Unified.cancel_order(%{category: "linear", symbol: "BTCUSDT", orderId: "abc123"})

  Or use the category-prefixed convenience functions defined in the main Endpoints module:
      Endpoints.spot_place_order(%{symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      Endpoints.linear_cancel_order(%{symbol: "BTCUSDT", orderId: "abc123"})
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Bybit.Endpoints

  alias ZenCex.Adapters.Bybit.Parser
  alias ZenCex.Adapters.Bybit.RequestHelper

  @endpoints [
    # Account endpoints
    %{
      operation: :get_wallet_balance,
      method: :get,
      path: "/v5/account/wallet-balance",
      requires_auth: true,
      weight: 1,
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_wallet_balance/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get wallet balance for the specified account type.

      ## Parameters

      - `accountType` (required) - Account type: "UNIFIED", "CONTRACT", "SPOT", "INVESTMENT", "OPTION"
      - `coin` (optional) - Filter by coin, e.g., "BTC", "USDT"

      ## Examples

          # Get unified account balance
          get_wallet_balance(%{accountType: "UNIFIED"})

          # Get spot account BTC balance
          get_wallet_balance(%{accountType: "SPOT", coin: "BTC"})

      ## Error Scenarios

      - `{:error, {:invalid_parameter, "Invalid accountType"}}` - Invalid account type
      - `{:error, {:permission_denied, "No permission"}}` - API key lacks permission
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },

    # Order Management endpoints
    %{
      operation: :place_order,
      method: :post,
      path: "/v5/order/create",
      requires_auth: true,
      weight: 1,
      timeout: 2_000,
      # Never retry order placement
      max_retries: 0,
      retry_on: [],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Place a new order.

      ## Required Parameters

      - `category` - Product type: "spot", "linear", "inverse", "option"
      - `symbol` - Trading pair, e.g., "BTCUSDT"
      - `side` - Order side: "Buy" or "Sell"
      - `orderType` - Order type: "Market", "Limit"
      - `qty` - Order quantity

      ## Optional Parameters

      - `price` - Limit price (required for Limit orders)
      - `timeInForce` - "GTC", "IOC", "FOK", "PostOnly"
      - `orderLinkId` - User-defined order ID
      - `isLeverage` - Whether to borrow (spot margin trade)
      - `triggerPrice` - Trigger price for stop orders
      - `reduceOnly` - Reduce position only (futures)
      - `closeOnTrigger` - Close position on trigger (futures)
      - `slTriggerBy` - Stop loss trigger price type
      - `tpTriggerBy` - Take profit trigger price type
      - `positionIdx` - Position index for hedge mode

      ## Examples

          # Spot market buy
          place_order(%{
            category: "spot",
            symbol: "BTCUSDT",
            side: "Buy",
            orderType: "Market",
            qty: "0.01"
          })

          # Linear futures limit order
          place_order(%{
            category: "linear",
            symbol: "BTCUSDT",
            side: "Buy",
            orderType: "Limit",
            qty: "0.01",
            price: "30000"
          })

      ## Error Scenarios

      - `{:error, {:insufficient_balance, "Insufficient balance"}}` - Not enough funds
      - `{:error, {:invalid_symbol, "Invalid symbol"}}` - Symbol not found
      - `{:error, {:invalid_order_qty, "Qty too small"}}` - Below minimum order size
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },
    %{
      operation: :cancel_order,
      method: :post,
      path: "/v5/order/cancel",
      requires_auth: true,
      weight: 1,
      timeout: 2_000,
      # Can retry cancellation
      max_retries: 2,
      retry_on: [:timeout],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Cancel an existing order.

      ## Required Parameters

      - `category` - Product type: "spot", "linear", "inverse", "option"
      - `symbol` - Trading pair

      ## Conditional Parameters (one required)

      - `orderId` - Exchange order ID
      - `orderLinkId` - User-defined order ID

      ## Examples

          # Cancel by order ID
          cancel_order(%{
            category: "spot",
            symbol: "BTCUSDT",
            orderId: "abc123"
          })

          # Cancel by user-defined ID
          cancel_order(%{
            category: "linear",
            symbol: "BTCUSDT",
            orderLinkId: "my-order-001"
          })

      ## Error Scenarios

      - `{:error, {:order_not_found, "Order does not exist"}}` - Order not found
      - `{:error, {:order_already_canceled, "Order already canceled"}}` - Already canceled
      - `{:error, {:invalid_parameter, "Missing orderId or orderLinkId"}}` - No ID provided
      """
    },
    %{
      operation: :cancel_all_orders,
      method: :post,
      path: "/v5/order/cancel-all",
      requires_auth: true,
      weight: 10,
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:timeout],
      response_parser: &Parser.parse_batch_cancel/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Cancel all open orders.

      ## Required Parameters

      - `category` - Product type: "spot", "linear", "inverse", "option"

      ## Optional Parameters

      - `symbol` - Filter by trading pair
      - `baseCoin` - Filter by base coin (linear/inverse only)
      - `settleCoin` - Filter by settle coin (linear/inverse only)

      ## Examples

          # Cancel all spot orders
          cancel_all_orders(%{category: "spot"})

          # Cancel all BTCUSDT linear orders
          cancel_all_orders(%{
            category: "linear",
            symbol: "BTCUSDT"
          })

      ## Error Scenarios

      - `{:error, {:no_orders_to_cancel, "No open orders"}}` - No orders found
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },
    %{
      operation: :get_order,
      method: :get,
      path: "/v5/order/realtime",
      requires_auth: true,
      weight: 1,
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_orders/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Query order details.

      ## Required Parameters

      - `category` - Product type: "spot", "linear", "inverse", "option"

      ## Optional Parameters

      - `symbol` - Trading pair
      - `orderId` - Exchange order ID
      - `orderLinkId` - User-defined order ID
      - `orderFilter` - Filter: "Order" (active), "StopOrder" (conditional)
      - `limit` - Result limit (default 20, max 500)

      ## Examples

          # Get specific order by ID
          get_order(%{
            category: "spot",
            orderId: "abc123"
          })

          # Get all active linear orders
          get_order(%{
            category: "linear",
            orderFilter: "Order"
          })

      ## Error Scenarios

      - `{:error, {:order_not_found, "Order does not exist"}}` - Order not found
      - `{:error, {:invalid_parameter, "Invalid category"}}` - Invalid category
      """
    },
    %{
      operation: :get_order_history,
      method: :get,
      path: "/v5/order/history",
      requires_auth: true,
      weight: 1,
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_orders/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get historical orders.

      ## Required Parameters

      - `category` - Product type: "spot", "linear", "inverse", "option"

      ## Optional Parameters

      - `symbol` - Trading pair
      - `orderId` - Filter by order ID
      - `orderLinkId` - Filter by user-defined ID
      - `orderStatus` - "Filled", "Cancelled", "Rejected"
      - `startTime` - Start timestamp (ms)
      - `endTime` - End timestamp (ms)
      - `limit` - Result limit (default 20, max 50)
      - `cursor` - Pagination cursor

      ## Examples

          # Get filled spot orders
          get_order_history(%{
            category: "spot",
            orderStatus: "Filled",
            limit: 50
          })

      ## Error Scenarios

      - `{:error, {:invalid_time_range, "Invalid time range"}}` - Time range too large
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    },

    # Position Management (Futures/Options only)
    %{
      operation: :get_positions,
      method: :get,
      path: "/v5/position/list",
      requires_auth: true,
      weight: 1,
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_positions/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get current positions (futures and options only).

      ## Required Parameters

      - `category` - Product type: "linear", "inverse", "option"

      ## Optional Parameters

      - `symbol` - Filter by trading pair
      - `baseCoin` - Filter by base coin
      - `settleCoin` - Filter by settle coin
      - `limit` - Result limit (default 20, max 200)
      - `cursor` - Pagination cursor

      ## Examples

          # Get all linear positions
          get_positions(%{category: "linear"})

          # Get specific position
          get_positions(%{
            category: "linear",
            symbol: "BTCUSDT"
          })

      ## Error Scenarios

      - `{:error, {:invalid_category, "Spot not supported"}}` - Spot has no positions
      - `{:error, {:permission_denied, "No futures permission"}}` - API key lacks permission
      """
    },
    %{
      operation: :set_leverage,
      method: :post,
      path: "/v5/position/set-leverage",
      requires_auth: true,
      weight: 1,
      timeout: 2_000,
      # Never retry leverage changes
      max_retries: 0,
      retry_on: [],
      response_parser: &Parser.parse_generic/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Set leverage for a symbol (futures only).

      ## Required Parameters

      - `category` - Product type: "linear" or "inverse"
      - `symbol` - Trading pair
      - `buyLeverage` - Buy side leverage (0.01 to max)
      - `sellLeverage` - Sell side leverage (0.01 to max)

      ## Examples

          # Set 10x leverage for both sides
          set_leverage(%{
            category: "linear",
            symbol: "BTCUSDT",
            buyLeverage: "10",
            sellLeverage: "10"
          })

      ## Error Scenarios

      - `{:error, {:invalid_leverage, "Leverage exceeds maximum"}}` - Too high leverage
      - `{:error, {:position_exists, "Cannot change with position"}}` - Has open position
      """
    },
    %{
      operation: :set_trading_stop,
      method: :post,
      path: "/v5/position/trading-stop",
      requires_auth: true,
      weight: 1,
      timeout: 2_000,
      # Never retry stop changes
      max_retries: 0,
      retry_on: [],
      response_parser: &Parser.parse_generic/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Set take profit, stop loss, and trailing stop for position.

      ## Required Parameters

      - `category` - Product type: "linear" or "inverse"
      - `symbol` - Trading pair

      ## Optional Parameters

      - `takeProfit` - Take profit price
      - `stopLoss` - Stop loss price
      - `trailingStop` - Trailing stop distance
      - `tpTriggerBy` - TP trigger type: "LastPrice", "IndexPrice", "MarkPrice"
      - `slTriggerBy` - SL trigger type: "LastPrice", "IndexPrice", "MarkPrice"
      - `activePrice` - Trailing stop activation price
      - `tpSize` - Partial TP size
      - `slSize` - Partial SL size
      - `positionIdx` - Position index (0: one-way, 1: buy hedge, 2: sell hedge)

      ## Examples

          # Set stop loss and take profit
          set_trading_stop(%{
            category: "linear",
            symbol: "BTCUSDT",
            takeProfit: "35000",
            stopLoss: "28000"
          })

      ## Error Scenarios

      - `{:error, {:position_not_found, "No position"}}` - No position exists
      - `{:error, {:invalid_price, "Invalid stop price"}}` - Stop price would trigger immediately
      """
    },

    # Trade History
    %{
      operation: :get_trades,
      method: :get,
      path: "/v5/execution/list",
      requires_auth: true,
      weight: 1,
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_trades/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get execution/trade history.

      ## Required Parameters

      - `category` - Product type: "spot", "linear", "inverse", "option"

      ## Optional Parameters

      - `symbol` - Filter by trading pair
      - `orderId` - Filter by order ID
      - `orderLinkId` - Filter by user-defined order ID
      - `startTime` - Start timestamp (ms)
      - `endTime` - End timestamp (ms)
      - `execType` - "Trade", "Funding", "AdlTrade", "BustTrade"
      - `limit` - Result limit (default 50, max 100)
      - `cursor` - Pagination cursor

      ## Examples

          # Get recent spot trades
          get_trades(%{
            category: "spot",
            limit: 100
          })

          # Get trades for specific order
          get_trades(%{
            category: "linear",
            orderId: "abc123"
          })

      ## Error Scenarios

      - `{:error, {:invalid_time_range, "Time range too large"}}` - Max 7 days
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    }
  ]

  # The EndpointRegistry macro automatically generates functions for all operations

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the unified API helper
    RequestHelper.execute_request_for_unified_api(config, params, opts)
  end
end
