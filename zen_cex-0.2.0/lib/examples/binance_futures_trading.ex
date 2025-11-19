defmodule ZenCex.Examples.BinanceFuturesTrading do
  @moduledoc """
  Futures trading examples for Binance (USD-M and COIN-M).

  Demonstrates futures trading operations from README.md:
  - USD-M futures (USDT-margined perpetual contracts)
  - COIN-M futures (coin-margined contracts)
  - Position management
  - Leverage configuration

  ## Usage

      # USD-M Futures
      {:ok, positions} = ZenCex.Examples.BinanceFuturesTrading.get_usdm_positions()
      {:ok, order} = ZenCex.Examples.BinanceFuturesTrading.place_usdm_market_order("BTCUSDT", "BUY", "0.001")

      # COIN-M Futures
      {:ok, positions} = ZenCex.Examples.BinanceFuturesTrading.get_coinm_positions()
      {:ok, order} = ZenCex.Examples.BinanceFuturesTrading.place_coinm_limit_order("BTCUSD_PERP", "BUY", "70000", "1")

  ## Requirements

  - Futures trading enabled on your testnet account
  - BINANCE_FUTURES_TEST_API_KEY and BINANCE_FUTURES_TEST_API_SECRET for testnet
  """

  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.UsdmFutures

  # USD-M Futures (USDT-margined)

  @doc """
  Get all USD-M futures positions.

  ## Examples

      {:ok, positions} = ZenCex.Examples.BinanceFuturesTrading.get_usdm_positions()
      open_positions = Enum.filter(positions, &(&1["positionAmt"] != "0"))

  ## Returns

  - `{:ok, [%{"symbol" => "BTCUSDT", "positionAmt" => "0.001", ...}, ...]}` - Position list
  - `{:error, reason}` - Query failed
  """
  @spec get_usdm_positions(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_usdm_positions(opts \\ []) do
    UsdmFutures.get_positions(%{}, opts)
  end

  @doc """
  Place a USD-M futures market order.

  ## Examples

      {:ok, order} = ZenCex.Examples.BinanceFuturesTrading.place_usdm_market_order("BTCUSDT", "BUY", "0.001")

  ## Parameters

  - `symbol` - Futures symbol (e.g., "BTCUSDT")
  - `side` - "BUY" or "SELL"
  - `quantity` - Amount in base asset units

  ## Returns

  - `{:ok, %{"orderId" => ..., ...}}` - Order placed
  - `{:error, reason}` - Order failed
  """
  @spec place_usdm_market_order(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_usdm_market_order(symbol, side, quantity, opts \\ [])
      when is_binary(symbol) and is_binary(side) and is_binary(quantity) do
    UsdmFutures.place_order(
      %{
        symbol: symbol,
        side: side,
        type: "MARKET",
        quantity: quantity
      },
      opts
    )
  end

  # COIN-M Futures (coin-margined)

  @doc """
  Get all COIN-M futures positions.

  ## Examples

      {:ok, positions} = ZenCex.Examples.BinanceFuturesTrading.get_coinm_positions()

  ## Returns

  - `{:ok, [%{"symbol" => "BTCUSD_PERP", ...}, ...]}` - Position list
  - `{:error, reason}` - Query failed
  """
  @spec get_coinm_positions(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_coinm_positions(opts \\ []) do
    CoinmFutures.get_positions(%{}, opts)
  end

  @doc """
  Place a COIN-M futures limit order.

  ## Examples

      {:ok, order} = ZenCex.Examples.BinanceFuturesTrading.place_coinm_limit_order(
        "BTCUSD_PERP",
        "BUY",
        "70000",
        "1"
      )

  ## Parameters

  - `symbol` - Coin-M symbol (e.g., "BTCUSD_PERP")
  - `side` - "BUY" or "SELL"
  - `price` - Limit price
  - `quantity` - Number of contracts

  ## Returns

  - `{:ok, %{"orderId" => ..., ...}}` - Order placed
  - `{:error, reason}` - Order failed
  """
  @spec place_coinm_limit_order(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def place_coinm_limit_order(symbol, side, price, quantity, opts \\ [])
      when is_binary(symbol) and is_binary(side) and is_binary(price) and is_binary(quantity) do
    CoinmFutures.place_order(
      %{
        symbol: symbol,
        side: side,
        type: "LIMIT",
        price: price,
        quantity: quantity,
        timeInForce: "GTC"
      },
      opts
    )
  end
end
