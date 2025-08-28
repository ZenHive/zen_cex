defmodule ZenCex.Adapters.Binance.MarketDataIntegrationTest do
  @moduledoc """
  Integration tests for Binance market data endpoints.

  These tests verify that the market data endpoints work correctly
  against the real Binance testnet API. Tests are organized by API type:
  spot, USDM futures, and COINM futures.
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.MarketData

  # Test symbols for different API types
  @spot_symbol "BTCUSDT"
  @usdm_symbol "BTCUSDT"
  @coinm_symbol "BTCUSD_PERP"

  # Common test limits to avoid magic numbers
  @default_order_book_limit 10
  @default_kline_limit 10
  @small_kline_limit 5
  @default_funding_limit 10

  describe "Spot Market Data" do
    test "get_ticker_price returns current price" do
      assert {:ok, data} = MarketData.get_ticker_price(%{symbol: @spot_symbol})
      assert is_map(data) or is_list(data)

      # If single symbol, should be a map
      if is_map(data) do
        assert data["symbol"] == @spot_symbol
        assert data["price"]
      end
    end

    test "get_ticker_24hr returns 24hr statistics" do
      assert {:ok, data} = MarketData.get_ticker_24hr(%{symbol: @spot_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @spot_symbol
        assert data["priceChange"]
        assert data["priceChangePercent"]
        assert data["volume"]
        assert data["lastPrice"]
      end
    end

    test "get_order_book returns depth data" do
      assert {:ok, data} = MarketData.get_order_book(%{symbol: @spot_symbol, limit: @default_order_book_limit})
      assert is_map(data)
      assert data["bids"]
      assert data["asks"]
      assert is_list(data["bids"])
      assert is_list(data["asks"])
    end

    test "get_recent_trades returns trade list" do
      assert {:ok, trades} = MarketData.get_recent_trades(%{symbol: @spot_symbol})
      assert is_list(trades)
      assert length(trades) > 0

      [first_trade | _] = trades
      assert first_trade["price"]
      assert first_trade["qty"]
      assert first_trade["time"]
    end

    test "get_klines returns candlestick data" do
      assert {:ok, klines} =
               MarketData.get_klines(%{
                 symbol: @spot_symbol,
                 interval: "1h",
                 limit: @default_kline_limit
               })

      assert is_list(klines)
      assert length(klines) > 0

      # Klines are arrays of values
      [first_kline | _] = klines
      assert is_list(first_kline)
      # OHLCV + extra fields
      assert length(first_kline) >= 11
    end

    test "get_avg_price returns average price" do
      assert {:ok, data} = MarketData.get_avg_price(%{symbol: @spot_symbol})
      assert is_map(data)
      assert data["mins"]
      assert data["price"]
    end

    test "get_exchange_info returns trading rules" do
      assert {:ok, data} = MarketData.get_exchange_info()
      assert is_map(data)
      assert data["timezone"]
      assert data["serverTime"]
      assert data["symbols"]
      assert is_list(data["symbols"])
    end

    test "get_book_ticker returns best bid/ask" do
      assert {:ok, data} = MarketData.get_book_ticker(%{symbol: @spot_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @spot_symbol
        assert data["bidPrice"]
        assert data["bidQty"]
        assert data["askPrice"]
        assert data["askQty"]
      end
    end
  end

  describe "USDM Futures Market Data" do
    test "usdm_get_ticker_price returns futures price" do
      assert {:ok, data} = MarketData.usdm_get_ticker_price(%{symbol: @usdm_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @usdm_symbol
        assert data["price"]
        assert data["time"]
      end
    end

    test "usdm_get_ticker_24hr returns futures 24hr stats" do
      assert {:ok, data} = MarketData.usdm_get_ticker_24hr(%{symbol: @usdm_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @usdm_symbol
        assert data["priceChange"]
        assert data["volume"]
      end
    end

    test "usdm_get_order_book returns futures depth" do
      assert {:ok, data} = MarketData.usdm_get_order_book(%{symbol: @usdm_symbol, limit: @default_order_book_limit})
      assert is_map(data)
      assert data["bids"]
      assert data["asks"]
    end

    test "usdm_get_recent_trades returns futures trades" do
      assert {:ok, trades} = MarketData.usdm_get_recent_trades(%{symbol: @usdm_symbol})
      assert is_list(trades)
      assert length(trades) > 0
    end

    test "usdm_get_klines returns futures candlesticks" do
      assert {:ok, klines} =
               MarketData.usdm_get_klines(%{
                 symbol: @usdm_symbol,
                 interval: "1h",
                 limit: @small_kline_limit
               })

      assert is_list(klines)
      assert length(klines) > 0
    end

    test "usdm_get_mark_price returns mark price and funding" do
      assert {:ok, data} = MarketData.usdm_get_mark_price(%{symbol: @usdm_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @usdm_symbol
        assert data["markPrice"]
        assert data["indexPrice"]
        # Funding rate might be in different field names
        assert data["fundingRate"] || data["lastFundingRate"]
        assert data["nextFundingTime"]
      end
    end

    test "usdm_get_funding_rate returns funding history" do
      assert {:ok, data} = MarketData.usdm_get_funding_rate(%{symbol: @usdm_symbol, limit: @default_funding_limit})
      assert is_list(data)

      if length(data) > 0 do
        [first | _] = data
        assert first["symbol"] == @usdm_symbol
        assert first["fundingRate"]
        assert first["fundingTime"]
      end
    end

    test "usdm_get_open_interest returns open interest" do
      assert {:ok, data} = MarketData.usdm_get_open_interest(%{symbol: @usdm_symbol})
      assert is_map(data)
      assert data["symbol"] == @usdm_symbol
      assert data["openInterest"]
      assert data["time"]
    end

    test "usdm_get_exchange_info returns futures trading rules" do
      assert {:ok, data} = MarketData.usdm_get_exchange_info()
      assert is_map(data)
      assert data["timezone"]
      assert data["serverTime"]
      assert data["symbols"]
    end
  end

  describe "COINM Futures Market Data" do
    test "coinm_get_ticker_price returns coin futures price" do
      assert {:ok, data} = MarketData.coinm_get_ticker_price(%{symbol: @coinm_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @coinm_symbol
        assert data["price"]
      end
    end

    test "coinm_get_ticker_24hr returns coin futures 24hr stats" do
      assert {:ok, data} = MarketData.coinm_get_ticker_24hr(%{symbol: @coinm_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @coinm_symbol
        assert data["volume"]
      end
    end

    test "coinm_get_order_book returns coin futures depth" do
      assert {:ok, data} = MarketData.coinm_get_order_book(%{symbol: @coinm_symbol, limit: @default_order_book_limit})
      assert is_map(data)
      assert data["bids"]
      assert data["asks"]
    end

    test "coinm_get_recent_trades returns coin futures trades" do
      assert {:ok, trades} = MarketData.coinm_get_recent_trades(%{symbol: @coinm_symbol})
      assert is_list(trades)
      assert length(trades) > 0
    end

    test "coinm_get_klines returns coin futures candlesticks" do
      assert {:ok, klines} =
               MarketData.coinm_get_klines(%{
                 symbol: @coinm_symbol,
                 interval: "1h",
                 limit: @small_kline_limit
               })

      assert is_list(klines)
      assert length(klines) > 0
    end

    test "coinm_get_mark_price returns coin futures mark price" do
      assert {:ok, data} = MarketData.coinm_get_mark_price(%{symbol: @coinm_symbol})
      assert is_map(data) or is_list(data)

      if is_map(data) do
        assert data["symbol"] == @coinm_symbol
        assert data["markPrice"]
      end
    end

    test "coinm_get_open_interest returns coin futures open interest" do
      assert {:ok, data} = MarketData.coinm_get_open_interest(%{symbol: @coinm_symbol})
      assert is_map(data)

      # Testnet returns empty map {} while production returns:
      # {"symbol": "BTCUSD_PERP", "pair": "BTCUSD", "openInterest": "...", "contractType": "PERPETUAL", "time": ...}
      # This is a known testnet limitation
      if map_size(data) > 0 do
        # Production response validation
        assert data["symbol"] == @coinm_symbol
        assert data["openInterest"]
        assert data["pair"]
        assert data["contractType"]
      else
        # Testnet returns empty map - this is expected
        assert data == %{}
      end
    end
  end

  describe "Error Handling" do
    test "handles invalid symbol gracefully" do
      assert {:error, _reason} = MarketData.get_ticker_price(%{symbol: "INVALID"})
    end

    test "handles missing required parameters" do
      assert {:error, _reason} = MarketData.get_order_book(%{})
    end

    test "handles invalid interval for klines" do
      assert {:error, _reason} =
               MarketData.get_klines(%{
                 symbol: @spot_symbol,
                 interval: "invalid"
               })
    end
  end
end
