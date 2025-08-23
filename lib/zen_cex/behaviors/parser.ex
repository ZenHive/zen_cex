defmodule ZenCex.Behaviors.Parser do
  @moduledoc """
  Behavior defining the response parsing contract for exchange adapters.

  Each exchange returns data in different formats. This behavior
  provides a consistent interface for parsing and normalizing responses.
  """

  @doc """
  Parses a position response from the exchange.

  ## Parameters
    - response: Raw response data from the exchange

  ## Returns
    - `{:ok, list()}` - List of normalized position maps
    - `{:error, reason}` - Parse error

  ## Normalized Position Format
    - `:symbol` - Trading pair/contract symbol
    - `:side` - :long or :short
    - `:size` - Position size (Decimal)
    - `:entry_price` - Average entry price (Decimal)
    - `:mark_price` - Current mark price (Decimal)
    - `:pnl` - Unrealized PnL (Decimal)
    - `:margin` - Margin/collateral used (Decimal)
    - `:timestamp` - Position update timestamp
  """
  @callback parse_positions(term()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Parses a balance response from the exchange.

  ## Parameters
    - response: Raw response data from the exchange

  ## Returns
    - `{:ok, list()}` - List of normalized balance maps
    - `{:error, reason}` - Parse error

  ## Normalized Balance Format
    - `:asset` - Asset symbol (e.g., "BTC", "USDT")
    - `:free` - Available balance (Decimal)
    - `:locked` - Locked in orders (Decimal)
    - `:total` - Total balance (Decimal)
  """
  @callback parse_balances(term()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Parses an order response from the exchange.

  ## Parameters
    - response: Raw response data from the exchange

  ## Returns
    - `{:ok, map()}` - Normalized order map
    - `{:error, reason}` - Parse error

  ## Normalized Order Format
    - `:order_id` - Exchange order ID
    - `:symbol` - Trading pair
    - `:side` - :buy or :sell
    - `:type` - :market, :limit, etc.
    - `:price` - Order price (Decimal)
    - `:quantity` - Order quantity (Decimal)
    - `:status` - :new, :filled, :cancelled, etc.
    - `:timestamp` - Order creation timestamp
  """
  @callback parse_order(term()) :: {:ok, map()} | {:error, term()}

  @doc """
  Parses market data from WebSocket streams.

  ## Parameters
    - data: Raw WebSocket message data

  ## Returns
    - `{:ok, map()}` - Normalized market data
    - `{:error, reason}` - Parse error
    - `:ignore` - Message should be ignored (heartbeat, etc.)

  ## Normalized Market Data Format
    - `:type` - :ticker, :trade, :orderbook, etc.
    - `:symbol` - Trading pair
    - `:data` - Type-specific data map
    - `:timestamp` - Event timestamp
  """
  @callback parse_market_data(term()) :: {:ok, map()} | {:error, term()} | :ignore

  @doc """
  Parses error responses from the exchange.

  ## Parameters
    - response: Raw error response

  ## Returns
    - `{:error, atom()}` - Normalized error atom
    - `{:error, {atom(), details}}` - Error with details

  ## Common Error Atoms
    - `:unauthorized` - Auth failure (401 status)
    - `:insufficient_balance` - Not enough funds
    - `:rate_limited` - Rate limit exceeded
    - `:invalid_symbol` - Unknown trading pair
    - `:order_not_found` - Order doesn't exist
    - `:exchange_error` - Generic exchange error
  """
  @callback parse_error(term()) :: {:error, atom()} | {:error, {atom(), term()}}

  @optional_callbacks parse_order: 1, parse_market_data: 1
end
