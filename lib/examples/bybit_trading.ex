defmodule ZenCex.Examples.BybitTrading do
  @moduledoc """
  Complete trading workflow examples for Bybit Unified API.

  Demonstrates Bybit's unified V5 API from README.md:288-326 which serves
  all trading categories (spot, linear, inverse, option) through a single
  endpoint distinguished by the `category` parameter.

  ## Category Values

  - `"spot"` - Spot trading
  - `"linear"` - USDT-margined perpetual futures
  - `"inverse"` - Coin-margined perpetual futures
  - `"option"` - Options trading

  ## Usage

      # Check server connectivity (no auth)
      {:ok, time} = ZenCex.Examples.BybitTrading.check_server_connectivity()

      # Place spot market order
      {:ok, order} = ZenCex.Examples.BybitTrading.place_spot_order("BTCUSDT", "Buy", "Market", "0.001")

      # Place linear futures market order
      {:ok, order} = ZenCex.Examples.BybitTrading.place_linear_futures_order("BTCUSDT", "Buy", "Market", "0.001")

      # Place inverse futures limit order
      {:ok, order} = ZenCex.Examples.BybitTrading.place_inverse_futures_order("BTCUSD", "Buy", "Limit", "70000", "100")

      # Get positions by category
      {:ok, positions} = ZenCex.Examples.BybitTrading.get_positions("linear")

  ## Requirements

  - BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET environment variables
  - BYBIT_TESTNET=true to enable testnet mode
  - Testnet account at https://testnet.bybit.com/
  """

  alias ZenCex.Adapters.Bybit.Common
  alias ZenCex.Adapters.Bybit.Unified

  @doc """
  Check server connectivity.

  This is a public endpoint that doesn't require authentication.
  Useful for verifying API connectivity and checking server time.

  ## Examples

      {:ok, time} = ZenCex.Examples.BybitTrading.check_server_connectivity()
      # %{server_time: 1704470400000, ...}

  ## Returns

  - `{:ok, %{server_time: timestamp}}` - Server time in milliseconds
  - `{:error, reason}` - Network or API error
  """
  @spec check_server_connectivity() :: {:ok, map()} | {:error, term()}
  def check_server_connectivity do
    Common.get_server_time()
  end

  @doc """
  Place a spot market order.

  Bybit spot orders use the unified API with `category: "spot"`.

  ## Examples

      # Buy 0.001 BTC at market price
      {:ok, order} = ZenCex.Examples.BybitTrading.place_spot_order(
        "BTCUSDT",
        "Buy",
        "Market",
        "0.001"
      )

      # Sell 0.001 BTC at market price
      {:ok, order} = ZenCex.Examples.BybitTrading.place_spot_order(
        "BTCUSDT",
        "Sell",
        "Market",
        "0.001"
      )

  ## Parameters

  - `symbol` - Trading pair (e.g., "BTCUSDT")
  - `side` - "Buy" or "Sell"
  - `order_type` - "Market" or "Limit"
  - `qty` - Quantity in base asset units

  ## Returns

  - `{:ok, %{"orderId" => ..., "orderStatus" => ...}}` - Order created
  - `{:error, reason}` - Order failed (insufficient balance, invalid symbol, etc.)
  """
  @spec place_spot_order(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def place_spot_order(symbol, side, order_type, qty, opts \\ [])
      when is_binary(symbol) and is_binary(side) and is_binary(order_type) and is_binary(qty) do
    Unified.place_order(
      %{
        category: "spot",
        symbol: symbol,
        side: side,
        orderType: order_type,
        qty: qty
      },
      opts
    )
  end

  @doc """
  Place a linear futures market order.

  Linear futures are USDT-margined perpetual contracts.
  Use `category: "linear"` in the unified API.

  ## Examples

      # Buy 0.001 BTC perpetual at market
      {:ok, order} = ZenCex.Examples.BybitTrading.place_linear_futures_order(
        "BTCUSDT",
        "Buy",
        "Market",
        "0.001"
      )

  ## Parameters

  - `symbol` - Trading pair (e.g., "BTCUSDT")
  - `side` - "Buy" or "Sell"
  - `order_type` - "Market" or "Limit"
  - `qty` - Quantity in base asset units

  ## Returns

  - `{:ok, %{"orderId" => ..., "orderStatus" => ...}}` - Order created
  - `{:error, reason}` - Order failed
  """
  @spec place_linear_futures_order(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def place_linear_futures_order(symbol, side, order_type, qty, opts \\ [])
      when is_binary(symbol) and is_binary(side) and is_binary(order_type) and is_binary(qty) do
    Unified.place_order(
      %{
        category: "linear",
        symbol: symbol,
        side: side,
        orderType: order_type,
        qty: qty
      },
      opts
    )
  end

  @doc """
  Place an inverse futures limit order.

  Inverse futures are coin-margined perpetual contracts.
  Use `category: "inverse"` in the unified API.

  Note: Quantity for inverse contracts is in USD value, not coin amount.

  ## Examples

      # Buy $100 worth of BTCUSD at $70,000
      {:ok, order} = ZenCex.Examples.BybitTrading.place_inverse_futures_order(
        "BTCUSD",
        "Buy",
        "Limit",
        "70000",
        "100"
      )

  ## Parameters

  - `symbol` - Trading pair (e.g., "BTCUSD")
  - `side` - "Buy" or "Sell"
  - `order_type` - "Market" or "Limit"
  - `price` - Limit price (required for Limit orders)
  - `qty` - Quantity in USD value

  ## Returns

  - `{:ok, %{"orderId" => ..., "orderStatus" => ...}}` - Order created
  - `{:error, reason}` - Order failed
  """
  @spec place_inverse_futures_order(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def place_inverse_futures_order(symbol, side, order_type, price, qty, opts \\ [])
      when is_binary(symbol) and is_binary(side) and is_binary(order_type) and is_binary(price) and is_binary(qty) do
    Unified.place_order(
      %{
        category: "inverse",
        symbol: symbol,
        side: side,
        orderType: order_type,
        price: price,
        qty: qty
      },
      opts
    )
  end

  @doc """
  Get positions for a specific category.

  Query all positions for a given trading category.

  **Note**: Bybit API requires either `symbol` or `settleCoin` parameter.
  Use the `settle_coin` option to query all positions for a settlement currency.

  ## Examples

      # Get linear futures positions (USDT-settled)
      {:ok, positions} = ZenCex.Examples.BybitTrading.get_positions("linear", settle_coin: "USDT")

      # Get inverse futures positions (BTC-settled)
      {:ok, positions} = ZenCex.Examples.BybitTrading.get_positions("inverse", settle_coin: "BTC")

      # Get specific symbol position
      {:ok, positions} = ZenCex.Examples.BybitTrading.get_positions("linear", symbol: "BTCUSDT")

  ## Parameters

  - `category` - "spot", "linear", "inverse", or "option"

  ## Options

  - `:settle_coin` - Settlement currency (e.g., "USDT", "BTC")
  - `:symbol` - Trading pair symbol (e.g., "BTCUSDT")
  - `:auth_credentials` - Authentication credentials map

  ## Returns

  - `{:ok, %{"list" => [position, ...]}}` - List of positions (Bybit uses string keys)
  - `{:error, reason}` - Query failed
  """
  @spec get_positions(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_positions(category, opts \\ []) when is_binary(category) do
    # Extract settle_coin or symbol option and build params
    params = %{category: category}

    params =
      cond do
        Keyword.has_key?(opts, :settle_coin) ->
          Map.put(params, :settleCoin, Keyword.get(opts, :settle_coin))

        Keyword.has_key?(opts, :symbol) ->
          Map.put(params, :symbol, Keyword.get(opts, :symbol))

        true ->
          params
      end

    # Remove settle_coin and symbol from opts before passing to API
    api_opts = Keyword.drop(opts, [:settle_coin, :symbol])

    Unified.get_position_list(params, api_opts)
  end
end
