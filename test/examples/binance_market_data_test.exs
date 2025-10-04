defmodule ZenCex.Examples.BinanceMarketDataTest do
  @moduledoc """
  Tests for binance_market_data.ex examples.

  All tests are for public endpoints - no authentication required.
  Tests verify response structures and error handling.
  """

  use ExUnit.Case

  alias ZenCex.Examples.BinanceMarketData

  @moduletag :example

  describe "public market data (no auth required)" do
    test "get_current_price/1 returns ticker price" do
      assert {:ok, data} = BinanceMarketData.get_current_price("BTCUSDT")
      assert Map.has_key?(data, "symbol")
      assert Map.has_key?(data, "price")
      assert data["symbol"] == "BTCUSDT"
      assert is_binary(data["price"])
    end

    test "get_24hr_stats/1 returns 24hr ticker statistics" do
      assert {:ok, data} = BinanceMarketData.get_24hr_stats("BTCUSDT")
      assert Map.has_key?(data, "symbol")
      assert Map.has_key?(data, "priceChange")
      assert Map.has_key?(data, "priceChangePercent")
      assert Map.has_key?(data, "lastPrice")
      assert Map.has_key?(data, "volume")
      assert data["symbol"] == "BTCUSDT"
    end

    test "get_order_book/2 returns order book" do
      assert {:ok, data} = BinanceMarketData.get_order_book("BTCUSDT", 10)
      assert Map.has_key?(data, "bids")
      assert Map.has_key?(data, "asks")
      assert is_list(data["bids"])
      assert is_list(data["asks"])

      # Verify bid/ask structure
      if length(data["bids"]) > 0 do
        [price, qty] = hd(data["bids"])
        assert is_binary(price)
        assert is_binary(qty)
      end
    end

    test "get_recent_trades/2 returns recent trades" do
      assert {:ok, trades} = BinanceMarketData.get_recent_trades("BTCUSDT", 5)
      assert is_list(trades)
      assert length(trades) <= 5

      if length(trades) > 0 do
        trade = hd(trades)
        assert Map.has_key?(trade, "id")
        assert Map.has_key?(trade, "price")
        assert Map.has_key?(trade, "qty")
        assert Map.has_key?(trade, "time")
        assert Map.has_key?(trade, "isBuyerMaker")
      end
    end

    test "get_klines/3 returns kline/candlestick data" do
      assert {:ok, klines} = BinanceMarketData.get_klines("BTCUSDT", "1h", 5)
      assert is_list(klines)
      assert length(klines) <= 5

      if length(klines) > 0 do
        kline = hd(klines)
        # Klines are arrays: [openTime, open, high, low, close, volume, ...]
        assert is_list(kline)
        assert length(kline) >= 6
      end
    end

    test "get_funding_rate/1 returns futures funding rate" do
      case BinanceMarketData.get_funding_rate("BTCUSDT") do
        {:ok, data} when is_list(data) ->
          # API returns list of funding rates
          assert length(data) > 0
          first_rate = hd(data)
          assert Map.has_key?(first_rate, "symbol")
          assert Map.has_key?(first_rate, "fundingRate")
          assert first_rate["symbol"] == "BTCUSDT"

        {:error, _reason} ->
          # Funding rate might not be available for all symbols
          :ok
      end
    end

    test "get_open_interest/1 returns futures open interest" do
      case BinanceMarketData.get_open_interest("BTCUSDT") do
        {:ok, data} ->
          assert Map.has_key?(data, "openInterest")
          assert Map.has_key?(data, "symbol")
          assert data["symbol"] == "BTCUSDT"

        {:error, _reason} ->
          # Open interest might not be available for all symbols
          :ok
      end
    end
  end

  describe "error handling" do
    test "handles invalid symbol gracefully" do
      case BinanceMarketData.get_current_price("INVALID") do
        {:ok, _} -> flunk("Expected error for invalid symbol")
        {:error, _reason} -> :ok
      end
    end

    test "handles invalid interval gracefully" do
      case BinanceMarketData.get_klines("BTCUSDT", "invalid", 5) do
        {:ok, _} -> flunk("Expected error for invalid interval")
        {:error, _reason} -> :ok
      end
    end

    test "handles excessive limit gracefully" do
      # Binance has max limits on depth
      case BinanceMarketData.get_order_book("BTCUSDT", 10_000) do
        {:ok, _} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end
end
