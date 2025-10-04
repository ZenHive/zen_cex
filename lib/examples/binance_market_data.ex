defmodule ZenCex.Examples.BinanceMarketData do
  @moduledoc """
  Market data fetching examples for Binance.

  Demonstrates public market data endpoints from README.md and usage-rules.md:
  - Ticker prices and 24hr statistics
  - Order book depth
  - Recent trades
  - Candlestick/klines data
  - Futures-specific data (funding rates, open interest)

  All endpoints are public and don't require authentication.

  ## Usage

      # Get current price
      {:ok, ticker} = ZenCex.Examples.BinanceMarketData.get_current_price("BTCUSDT")

      # Get 24hr stats
      {:ok, stats} = ZenCex.Examples.BinanceMarketData.get_24hr_stats("BTCUSDT")

      # Get order book
      {:ok, book} = ZenCex.Examples.BinanceMarketData.get_order_book("BTCUSDT", 20)

      # Get candlestick data
      {:ok, klines} = ZenCex.Examples.BinanceMarketData.get_klines("BTCUSDT", "1h", 100)

      # Get futures funding rate
      {:ok, funding} = ZenCex.Examples.BinanceMarketData.get_funding_rate("BTCUSDT")
  """

  alias ZenCex.Adapters.Binance.MarketData

  @doc """
  Get current ticker price for a symbol.

  ## Examples

      {:ok, ticker} = ZenCex.Examples.BinanceMarketData.get_current_price("BTCUSDT")
      price = ticker["price"]

  ## Parameters

  - `symbol` - Trading pair (e.g., "BTCUSDT")

  ## Returns

  - `{:ok, %{"symbol" => "BTCUSDT", "price" => "67000.00"}}` - Current price
  - `{:error, reason}` - Invalid symbol or network error
  """
  @spec get_current_price(String.t()) :: {:ok, map()} | {:error, term()}
  def get_current_price(symbol) when is_binary(symbol) do
    MarketData.get_ticker_price(%{symbol: symbol})
  end

  @doc """
  Get 24-hour ticker statistics.

  ## Examples

      {:ok, stats} = ZenCex.Examples.BinanceMarketData.get_24hr_stats("BTCUSDT")
      volume = stats["volume"]
      high = stats["highPrice"]
      low = stats["lowPrice"]

  ## Parameters

  - `symbol` - Trading pair

  ## Returns

  - `{:ok, %{"volume" => "...", "highPrice" => "...", "lowPrice" => "...", ...}}` - 24hr stats
  - `{:error, reason}` - Query failed
  """
  @spec get_24hr_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def get_24hr_stats(symbol) when is_binary(symbol) do
    MarketData.get_ticker_24hr(%{symbol: symbol})
  end

  @doc """
  Get order book depth.

  ## Examples

      {:ok, book} = ZenCex.Examples.BinanceMarketData.get_order_book("BTCUSDT", 20)
      best_bid = hd(book["bids"])  # [price, quantity]
      best_ask = hd(book["asks"])

  ## Parameters

  - `symbol` - Trading pair
  - `limit` - Depth limit (5, 10, 20, 50, 100, 500, 1000, 5000)

  ## Returns

  - `{:ok, %{"bids" => [[price, qty], ...], "asks" => [[price, qty], ...]}}` - Order book
  - `{:error, reason}` - Query failed
  """
  @spec get_order_book(String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def get_order_book(symbol, limit \\ 20) when is_binary(symbol) and is_integer(limit) do
    MarketData.get_order_book(%{symbol: symbol, limit: limit})
  end

  @doc """
  Get recent trades.

  ## Parameters
    * `symbol` - Trading pair
    * `limit` - Number of trades (default 500, max 1000)

  ## Examples

      {:ok, trades} = get_recent_trades("BTCUSDT", 10)
      # trades is a list of trade maps with price, quantity, and time data
      [first_trade | _] = trades
      first_trade["price"]  # "45000.00"
      first_trade["qty"]    # "0.5"

  ## Returns

  - `{:ok, [%{"price" => "...", "qty" => "...", "time" => ...}, ...]}` - Trade list
  - `{:error, reason}` - Query failed
  """
  @spec get_recent_trades(String.t(), integer()) :: {:ok, list(map())} | {:error, term()}
  def get_recent_trades(symbol, limit \\ 10) when is_binary(symbol) and is_integer(limit) do
    MarketData.get_recent_trades(%{symbol: symbol, limit: limit})
  end

  @doc """
  Get candlestick/klines data.

  ## Examples

      {:ok, klines} = ZenCex.Examples.BinanceMarketData.get_klines("BTCUSDT", "1h", 100)
      # Each kline: [open_time, open, high, low, close, volume, ...]

  ## Parameters

  - `symbol` - Trading pair
  - `interval` - Candlestick interval ("1m", "5m", "15m", "1h", "4h", "1d", etc.)
  - `limit` - Number of klines (default 500, max 1000)

  ## Returns

  - `{:ok, [[open_time, open, high, low, close, volume, ...], ...]}` - Klines data
  - `{:error, reason}` - Query failed
  """
  @spec get_klines(String.t(), String.t(), integer()) :: {:ok, list()} | {:error, term()}
  def get_klines(symbol, interval, limit \\ 100) when is_binary(symbol) and is_binary(interval) and is_integer(limit) do
    MarketData.get_klines(%{
      symbol: symbol,
      interval: interval,
      limit: limit
    })
  end

  # Futures-specific market data

  @doc """
  Get funding rate history for USD-M futures.

  ## Examples

      {:ok, funding_history} = ZenCex.Examples.BinanceMarketData.get_funding_rate("BTCUSDT")
      latest = hd(funding_history)
      current_rate = latest["fundingRate"]

  ## Parameters

  - `symbol` - Futures symbol

  ## Returns

  - `{:ok, [%{"fundingRate" => "0.0001", "fundingTime" => ..., "symbol" => "BTCUSDT"}, ...]}` - Funding rate history
  - `{:error, reason}` - Query failed
  """
  @spec get_funding_rate(String.t()) :: {:ok, list(map())} | {:error, term()}
  def get_funding_rate(symbol) when is_binary(symbol) do
    MarketData.usdm_get_funding_rate(%{symbol: symbol})
  end

  @doc """
  Get open interest for USD-M futures.

  ## Examples

      {:ok, oi} = ZenCex.Examples.BinanceMarketData.get_open_interest("BTCUSDT")
      open_interest = oi["openInterest"]

  ## Parameters

  - `symbol` - Futures symbol

  ## Returns

  - `{:ok, %{"openInterest" => "12345.67", "symbol" => "BTCUSDT", ...}}` - OI data
  - `{:error, reason}` - Query failed
  """
  @spec get_open_interest(String.t()) :: {:ok, map()} | {:error, term()}
  def get_open_interest(symbol) when is_binary(symbol) do
    MarketData.usdm_get_open_interest(%{symbol: symbol})
  end
end
