defmodule ZenCex.Cache.Market do
  @moduledoc """
  Market data caching utilities for zen_cex exchange operations.

  Provides convenient wrappers around `ZenCex.Core.Cache` with market data-specific
  key generation and TTL management. Optimized for common trading patterns where
  market data is accessed frequently but doesn't change rapidly.

  ## Usage

      # Cache ticker data for 30 seconds
      ticker_data = %{price: "45000.00", volume: "1200.50"}
      ZenCex.Cache.Market.put_ticker(:binance, "BTCUSDT", ticker_data)

      # Retrieve cached ticker
      {:ok, ticker} = ZenCex.Cache.Market.get_ticker(:binance, "BTCUSDT")

      # Cache funding rate for 5 minutes
      funding_data = %{rate: 0.0001, interval_hours: 8}
      ZenCex.Cache.Market.put_funding_rate(:bybit, "ETHUSDT", funding_data)

  ## TTL Guidelines

  - **Tickers**: 30-60 seconds (price changes frequently)
  - **Funding rates**: 5-15 minutes (updated every 8 hours)
  - **24hr stats**: 60-300 seconds (updated periodically)
  - **Order book snapshots**: 5-30 seconds (depends on depth)

  """

  alias ZenCex.Core.Cache

  # Default TTL values in seconds
  # Prices change frequently
  @ticker_ttl_seconds 30
  @default_ticker_ttl @ticker_ttl_seconds

  # Updated every 8 hours typically
  @funding_rate_ttl_minutes 5
  @default_funding_rate_ttl @funding_rate_ttl_minutes * 60

  # Updated periodically
  @stats_24hr_ttl_seconds 60
  @default_stats_24hr_ttl @stats_24hr_ttl_seconds

  # High frequency data
  @orderbook_ttl_seconds 15
  @default_orderbook_ttl @orderbook_ttl_seconds

  @type exchange :: atom()
  @type symbol :: binary()
  @type market_data :: map() | list() | binary()

  # Ticker data caching

  @doc """
  Gets cached ticker data for a specific exchange and symbol.

  ## Examples

      {:ok, %{price: "45000.00", volume: "1200.50"}} =
        ZenCex.Cache.Market.get_ticker(:binance, "BTCUSDT")

      :error = ZenCex.Cache.Market.get_ticker(:binance, "NONEXISTENT")

  """
  @spec get_ticker(exchange(), symbol()) :: {:ok, market_data()} | {:error, :not_found | :expired}
  def get_ticker(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    key = ticker_key(exchange, symbol)
    Cache.get(key)
  end

  @doc """
  Caches ticker data with default or custom TTL.

  ## Examples

      # Use default TTL (30 seconds)
      ZenCex.Cache.Market.put_ticker(:binance, "BTCUSDT", ticker_data)

      # Custom TTL (60 seconds)
      ZenCex.Cache.Market.put_ticker(:binance, "BTCUSDT", ticker_data, 60)

  """
  @spec put_ticker(exchange(), symbol(), market_data(), pos_integer()) :: :ok
  def put_ticker(exchange, symbol, data, ttl_seconds \\ @default_ticker_ttl)
      when is_atom(exchange) and is_binary(symbol) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    key = ticker_key(exchange, symbol)
    Cache.put(key, data, ttl_seconds)
  end

  # Funding rate caching

  @doc """
  Gets cached funding rate data for a specific exchange and symbol.

  ## Examples

      {:ok, %{rate: 0.0001, interval_hours: 8}} =
        ZenCex.Cache.Market.get_funding_rate(:bybit, "ETHUSDT")

      :error = ZenCex.Cache.Market.get_funding_rate(:binance, "BTCUSDT")

  """
  @spec get_funding_rate(exchange(), symbol()) :: {:ok, market_data()} | {:error, :not_found | :expired}
  def get_funding_rate(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    key = funding_rate_key(exchange, symbol)
    Cache.get(key)
  end

  @doc """
  Caches funding rate data with default or custom TTL.

  ## Examples

      # Use default TTL (5 minutes)
      ZenCex.Cache.Market.put_funding_rate(:bybit, "ETHUSDT", funding_data)

      # Custom TTL (15 minutes)
      ZenCex.Cache.Market.put_funding_rate(:bybit, "ETHUSDT", funding_data, 900)

  """
  @spec put_funding_rate(exchange(), symbol(), market_data(), pos_integer()) :: :ok
  def put_funding_rate(exchange, symbol, data, ttl_seconds \\ @default_funding_rate_ttl)
      when is_atom(exchange) and is_binary(symbol) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    key = funding_rate_key(exchange, symbol)
    Cache.put(key, data, ttl_seconds)
  end

  # 24hr statistics caching

  @doc """
  Gets cached 24hr statistics for a specific exchange and symbol.

  ## Examples

      {:ok, %{volume: "5420.12", change_percent: "2.45"}} =
        ZenCex.Cache.Market.get_24hr_stats(:binance, "BTCUSDT")

  """
  @spec get_24hr_stats(exchange(), symbol()) :: {:ok, market_data()} | {:error, :not_found | :expired}
  def get_24hr_stats(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    key = stats_24hr_key(exchange, symbol)
    Cache.get(key)
  end

  @doc """
  Caches 24hr statistics with default or custom TTL.

  ## Examples

      # Use default TTL (60 seconds)
      ZenCex.Cache.Market.put_24hr_stats(:binance, "BTCUSDT", stats_data)

      # Custom TTL (5 minutes)
      ZenCex.Cache.Market.put_24hr_stats(:binance, "BTCUSDT", stats_data, 300)

  """
  @spec put_24hr_stats(exchange(), symbol(), market_data(), pos_integer()) :: :ok
  def put_24hr_stats(exchange, symbol, data, ttl_seconds \\ @default_stats_24hr_ttl)
      when is_atom(exchange) and is_binary(symbol) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    key = stats_24hr_key(exchange, symbol)
    Cache.put(key, data, ttl_seconds)
  end

  # Order book caching

  @doc """
  Gets cached order book snapshot for a specific exchange and symbol.

  ## Examples

      {:ok, %{bids: [...], asks: [...]}} =
        ZenCex.Cache.Market.get_orderbook(:binance, "BTCUSDT")

  """
  @spec get_orderbook(exchange(), symbol()) :: {:ok, market_data()} | {:error, :not_found | :expired}
  def get_orderbook(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    key = orderbook_key(exchange, symbol)
    Cache.get(key)
  end

  @doc """
  Caches order book snapshot with default or custom TTL.

  ## Examples

      # Use default TTL (15 seconds)
      ZenCex.Cache.Market.put_orderbook(:binance, "BTCUSDT", orderbook_data)

      # Custom TTL (30 seconds)
      ZenCex.Cache.Market.put_orderbook(:binance, "BTCUSDT", orderbook_data, 30)

  """
  @spec put_orderbook(exchange(), symbol(), market_data(), pos_integer()) :: :ok
  def put_orderbook(exchange, symbol, data, ttl_seconds \\ @default_orderbook_ttl)
      when is_atom(exchange) and is_binary(symbol) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    key = orderbook_key(exchange, symbol)
    Cache.put(key, data, ttl_seconds)
  end

  # Generic market data operations

  @doc """
  Gets any cached market data using a custom key suffix.

  Useful for caching custom market data types not covered by specific functions.

  ## Examples

      # Cache and retrieve kline data
      ZenCex.Cache.Market.put_market_data(:binance, "BTCUSDT", "klines_1h", kline_data, 300)
      {:ok, klines} = ZenCex.Cache.Market.get_market_data(:binance, "BTCUSDT", "klines_1h")

  """
  @spec get_market_data(exchange(), symbol(), binary()) :: {:ok, market_data()} | {:error, :not_found | :expired}
  def get_market_data(exchange, symbol, data_type)
      when is_atom(exchange) and is_binary(symbol) and is_binary(data_type) do
    key = market_data_key(exchange, symbol, data_type)
    Cache.get(key)
  end

  @doc """
  Caches custom market data with a specific TTL.

  ## Examples

      # Cache historical trades for 2 minutes
      ZenCex.Cache.Market.put_market_data(:bybit, "ETHUSDT", "trades", trades_data, 120)

  """
  @spec put_market_data(exchange(), symbol(), binary(), market_data(), pos_integer()) :: :ok
  def put_market_data(exchange, symbol, data_type, data, ttl_seconds)
      when is_atom(exchange) and is_binary(symbol) and is_binary(data_type) and is_integer(ttl_seconds) and
             ttl_seconds > 0 do
    key = market_data_key(exchange, symbol, data_type)
    Cache.put(key, data, ttl_seconds)
  end

  # Bulk operations

  @doc """
  Clears all cached market data for a specific exchange.

  Useful when an exchange goes offline or needs data refresh.

  ## Examples

      # Clear all Binance cached data
      ZenCex.Cache.Market.clear_exchange(:binance)

  """
  @spec clear_exchange(exchange()) :: {:ok, non_neg_integer()}
  def clear_exchange(exchange) when is_atom(exchange) do
    # Clear all cache entries for this exchange
    # Keys are formatted as "market:type:exchange:symbol"
    # Use efficient wildcard pattern matching to match exchange in third position
    pattern = "market:*:#{exchange}:*"
    {:ok, count} = Cache.clear_pattern(pattern)
    {:ok, count}
  end

  @doc """
  Clears all cached data for a specific symbol across all exchanges.

  ## Examples

      # Clear all BTCUSDT data from all exchanges
      ZenCex.Cache.Market.clear_symbol("BTCUSDT")

  """
  @spec clear_symbol(symbol()) :: {:ok, non_neg_integer()}
  def clear_symbol(symbol) when is_binary(symbol) do
    # Clear all cache entries for this symbol
    # Use efficient wildcard pattern matching to match symbol at end of key
    pattern = "market:*:*:#{symbol}"
    {:ok, count} = Cache.clear_pattern(pattern)
    {:ok, count}
  end

  @doc """
  Clears all cached data of a specific type across all exchanges and symbols.

  ## Examples

      # Clear all ticker data
      ZenCex.Cache.Market.clear_data_type("ticker")

      # Clear all funding rate data
      ZenCex.Cache.Market.clear_data_type("funding")

  """
  @spec clear_data_type(binary()) :: {:ok, non_neg_integer()}
  def clear_data_type(data_type) when is_binary(data_type) do
    # Clear all cache entries of specific data type
    # Use efficient wildcard pattern matching to match data type in second position
    pattern = "market:#{data_type}:*"
    {:ok, count} = Cache.clear_pattern(pattern)
    {:ok, count}
  end

  @doc """
  Clears all market data cache entries.

  ## Examples

      # Clear everything in market cache
      ZenCex.Cache.Market.clear_all()

  """
  @spec clear_all() :: {:ok, non_neg_integer()}
  def clear_all do
    # Clear all market cache entries using prefix pattern
    pattern = "market:"
    {:ok, count} = Cache.clear_pattern(pattern)
    {:ok, count}
  end

  # Key generation functions (exposed for testing)

  @doc false
  def ticker_key(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    "market:ticker:#{exchange}:#{symbol}"
  end

  @doc false
  def funding_rate_key(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    "market:funding:#{exchange}:#{symbol}"
  end

  @doc false
  def stats_24hr_key(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    "market:stats24h:#{exchange}:#{symbol}"
  end

  @doc false
  def orderbook_key(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    "market:orderbook:#{exchange}:#{symbol}"
  end

  @doc false
  def market_data_key(exchange, symbol, data_type)
      when is_atom(exchange) and is_binary(symbol) and is_binary(data_type) do
    "market:#{data_type}:#{exchange}:#{symbol}"
  end
end
