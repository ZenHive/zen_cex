defmodule ZenCex.Examples.BinanceSpotTrading do
  @moduledoc """
  Complete spot trading workflow examples for Binance.

  Demonstrates all spot trading operations from README.md:
  - Getting account balances
  - Placing market orders
  - Placing limit orders
  - Checking order status
  - Canceling orders
  - Managing open orders

  All examples use the testnet for safety.

  ## Usage

      # Get current balances
      {:ok, balances} = ZenCex.Examples.BinanceSpotTrading.get_current_balances()

      # Place a market buy order
      {:ok, order} = ZenCex.Examples.BinanceSpotTrading.place_market_buy("BTCUSDT", "0.001")

      # Place a limit sell order
      {:ok, order} = ZenCex.Examples.BinanceSpotTrading.place_limit_sell("BTCUSDT", "70000", "0.001")

      # Check order status
      {:ok, status} = ZenCex.Examples.BinanceSpotTrading.check_order_status("BTCUSDT", order_id)

      # Cancel an order
      {:ok, _} = ZenCex.Examples.BinanceSpotTrading.cancel_order("BTCUSDT", order_id)

  ## Requirements

  - BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET environment variables
  - Testnet account with some balance for testing orders
  """

  alias ZenCex.Adapters.Binance.Spot

  @doc """
  Get current account balances.

  Returns all assets with non-zero balances.

  ## Examples

      {:ok, balances} = ZenCex.Examples.BinanceSpotTrading.get_current_balances()
      # Find specific asset
      btc = Enum.find(balances, &(&1["asset"] == "BTC"))

  ## Returns

  - `{:ok, [%{"asset" => "BTC", "free" => "0.001", "locked" => "0"}, ...]}` - Balances list
  - `{:error, reason}` - Failed to fetch balances
  """
  @spec get_current_balances(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_current_balances(opts \\ []) do
    Spot.get_balances(%{}, opts)
  end

  @doc """
  Place a market buy order.

  Market orders execute immediately at the current market price.

  ## Examples

      {:ok, order} = ZenCex.Examples.BinanceSpotTrading.place_market_buy("BTCUSDT", "0.001")
      order_id = order["orderId"]

  ## Parameters

  - `symbol` - Trading pair (e.g., "BTCUSDT")
  - `quantity` - Amount to buy in base asset units

  ## Returns

  - `{:ok, %{"orderId" => ..., "status" => "FILLED", ...}}` - Order executed
  - `{:error, reason}` - Order failed (insufficient balance, invalid symbol, etc.)
  """
  @spec place_market_buy(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_market_buy(symbol, quantity, opts \\ []) when is_binary(symbol) and is_binary(quantity) do
    Spot.place_order(
      %{
        symbol: symbol,
        side: "BUY",
        type: "MARKET",
        quantity: quantity
      },
      opts
    )
  end

  @doc """
  Place a limit sell order.

  Limit orders wait for the specified price before executing.

  ## Examples

      {:ok, order} = ZenCex.Examples.BinanceSpotTrading.place_limit_sell("BTCUSDT", "70000", "0.001")
      # Order will execute when price reaches 70000 or higher

  ## Parameters

  - `symbol` - Trading pair (e.g., "BTCUSDT")
  - `price` - Limit price as string
  - `quantity` - Amount to sell in base asset units

  ## Returns

  - `{:ok, %{"orderId" => ..., "status" => "NEW", ...}}` - Order placed
  - `{:error, reason}` - Order failed
  """
  @spec place_limit_sell(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_limit_sell(symbol, price, quantity, opts \\ [])
      when is_binary(symbol) and is_binary(price) and is_binary(quantity) do
    Spot.place_order(
      %{
        symbol: symbol,
        side: "SELL",
        type: "LIMIT",
        price: price,
        quantity: quantity,
        timeInForce: "GTC"
      },
      opts
    )
  end

  @doc """
  Place a limit buy order.

  ## Examples

      {:ok, order} = ZenCex.Examples.BinanceSpotTrading.place_limit_buy("BTCUSDT", "65000", "0.001")

  ## Parameters

  - `symbol` - Trading pair
  - `price` - Limit price
  - `quantity` - Amount to buy

  ## Returns

  - `{:ok, %{"orderId" => ..., ...}}` - Order placed
  - `{:error, reason}` - Order failed
  """
  @spec place_limit_buy(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_limit_buy(symbol, price, quantity, opts \\ [])
      when is_binary(symbol) and is_binary(price) and is_binary(quantity) do
    Spot.place_order(
      %{
        symbol: symbol,
        side: "BUY",
        type: "LIMIT",
        price: price,
        quantity: quantity,
        timeInForce: "GTC"
      },
      opts
    )
  end

  @doc """
  Check the status of an order.

  ## Examples

      {:ok, status} = ZenCex.Examples.BinanceSpotTrading.check_order_status("BTCUSDT", 12345)
      status["status"]  # "NEW", "FILLED", "PARTIALLY_FILLED", "CANCELED", etc.

  ## Parameters

  - `symbol` - Trading pair
  - `order_id` - Order ID returned from place_order

  ## Returns

  - `{:ok, %{"status" => ..., "executedQty" => ..., ...}}` - Order details
  - `{:error, reason}` - Order not found or query failed
  """
  @spec check_order_status(String.t(), integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def check_order_status(symbol, order_id, opts \\ []) when is_binary(symbol) and is_integer(order_id) do
    Spot.get_order(
      %{
        symbol: symbol,
        orderId: order_id
      },
      opts
    )
  end

  @doc """
  Cancel an open order.

  ## Examples

      {:ok, _} = ZenCex.Examples.BinanceSpotTrading.cancel_order("BTCUSDT", 12345)

  ## Parameters

  - `symbol` - Trading pair
  - `order_id` - Order ID to cancel

  ## Returns

  - `{:ok, %{"orderId" => ..., "status" => "CANCELED", ...}}` - Order canceled
  - `{:error, reason}` - Order not found or already filled
  """
  @spec cancel_order(String.t(), integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def cancel_order(symbol, order_id, opts \\ []) when is_binary(symbol) and is_integer(order_id) do
    Spot.cancel_order(
      %{
        symbol: symbol,
        orderId: order_id
      },
      opts
    )
  end

  @doc """
  Get all open orders for a symbol.

  ## Examples

      {:ok, orders} = ZenCex.Examples.BinanceSpotTrading.get_open_orders("BTCUSDT")
      Enum.each(orders, fn order -> IO.inspect(order["orderId"]) end)

  ## Parameters

  - `symbol` - Trading pair (optional, if nil returns all symbols)

  ## Returns

  - `{:ok, [%{"orderId" => ..., "status" => "NEW", ...}, ...]}` - List of open orders
  - `{:error, reason}` - Query failed
  """
  @spec get_open_orders(String.t() | nil, keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_open_orders(symbol \\ nil, opts \\ [])

  def get_open_orders(nil, opts) do
    Spot.get_open_orders(%{}, opts)
  end

  def get_open_orders(symbol, opts) when is_binary(symbol) do
    Spot.get_open_orders(%{symbol: symbol}, opts)
  end

  @doc """
  Cancel all open orders for a symbol.

  ## Examples

      {:ok, canceled} = ZenCex.Examples.BinanceSpotTrading.cancel_all_orders("BTCUSDT")
      length(canceled)  # Number of orders canceled

  ## Parameters

  - `symbol` - Trading pair

  ## Returns

  - `{:ok, [%{"orderId" => ..., ...}, ...]}` - List of canceled orders
  - `{:error, reason}` - Cancelation failed
  """
  @spec cancel_all_orders(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def cancel_all_orders(symbol, opts \\ []) when is_binary(symbol) do
    Spot.delete_open_orders(%{symbol: symbol}, opts)
  end
end
