defmodule ZenCex.Adapters.Bybit.MarketDataIntegrationTest do
  @moduledoc """
  Integration tests for Bybit market data endpoints.

  These tests run against the real Bybit testnet API to ensure:
  - Endpoints return expected data structures
  - Response parsing works correctly
  - Rate limiting is respected
  - Public endpoints work without authentication
  """

  use ZenCex.IntegrationCase, exchange: :bybit, api_type: :market_data

  alias ZenCex.Adapters.Bybit.Endpoints
  alias ZenCex.Adapters.Bybit.MarketData

  @test_symbol_spot "BTCUSDT"
  @test_symbol_linear "BTCUSDT"

  # Timeout for market data endpoints (typically faster than trading)
  @timeout_ms 5_000

  describe "ticker endpoints" do
    @tag :integration
    test "get_tickers returns spot ticker data" do
      assert {:ok, result} =
               Endpoints.get_tickers(%{
                 category: "spot",
                 symbol: @test_symbol_spot
               })

      assert %{"category" => "spot", "list" => list} = result
      assert is_list(list)

      if length(list) > 0 do
        [ticker | _] = list
        assert_ticker_fields(ticker)
      end
    end

    @tag :integration
    test "get_tickers returns linear futures ticker data" do
      assert {:ok, result} =
               Endpoints.get_tickers(%{
                 category: "linear",
                 symbol: @test_symbol_linear
               })

      assert %{"category" => "linear", "list" => list} = result
      assert is_list(list)

      if length(list) > 0 do
        [ticker | _] = list
        assert_ticker_fields(ticker)
      end
    end
  end

  describe "order book endpoints" do
    @tag :integration
    test "get_orderbook returns spot order book" do
      assert {:ok, result} =
               Endpoints.get_orderbook(%{
                 category: "spot",
                 symbol: @test_symbol_spot,
                 limit: 10
               })

      # Bybit returns different structure for order book
      assert %{"s" => symbol, "b" => bids, "a" => asks} = result
      assert symbol == @test_symbol_spot
      assert is_list(bids)
      assert is_list(asks)
      assert length(bids) <= 10
      assert length(asks) <= 10

      # Each level should be [price, quantity]
      if length(bids) > 0 do
        [bid_price, bid_qty] = hd(bids)
        assert is_binary(bid_price)
        assert is_binary(bid_qty)
      end
    end

    @tag :integration
    test "get_orderbook returns linear futures order book" do
      assert {:ok, result} =
               Endpoints.get_orderbook(%{
                 category: "linear",
                 symbol: @test_symbol_linear,
                 limit: 5
               })

      assert %{"s" => symbol, "b" => bids, "a" => asks} = result
      assert symbol == @test_symbol_linear
      assert length(bids) <= 5
      assert length(asks) <= 5
    end
  end

  describe "klines/candlestick endpoints" do
    @tag :integration
    test "get_klines returns spot candlestick data" do
      assert {:ok, result} =
               Endpoints.get_klines(%{
                 category: "spot",
                 symbol: @test_symbol_spot,
                 # 5 minutes
                 interval: "5",
                 limit: 10
               })

      assert %{"category" => "spot", "symbol" => symbol, "list" => klines} = result
      assert symbol == @test_symbol_spot
      assert is_list(klines)
      assert length(klines) <= 10

      if length(klines) > 0 do
        # Each kline: [timestamp, open, high, low, close, volume, turnover]
        [timestamp, open, high, low, close, volume, turnover] = hd(klines)
        assert is_binary(timestamp)
        assert is_binary(open)
        assert is_binary(high)
        assert is_binary(low)
        assert is_binary(close)
        assert is_binary(volume)
        assert is_binary(turnover)
      end
    end

    @tag :integration
    test "get_klines returns linear futures candlestick data" do
      assert {:ok, result} =
               Endpoints.get_klines(%{
                 category: "linear",
                 symbol: @test_symbol_linear,
                 # 15 minutes
                 interval: "15",
                 limit: 5
               })

      assert %{"category" => "linear", "list" => klines} = result
      assert length(klines) <= 5
    end

    @tag :integration
    test "get_mark_price_klines returns mark price candlesticks" do
      assert {:ok, result} =
               Endpoints.get_mark_price_klines(%{
                 category: "linear",
                 symbol: @test_symbol_linear,
                 # 1 hour
                 interval: "60",
                 limit: 3
               })

      assert %{"category" => "linear", "list" => klines} = result
      assert is_list(klines)
    end
  end

  describe "recent trades endpoints" do
    @tag :integration
    test "get_recent_trades returns spot trades" do
      assert {:ok, result} =
               Endpoints.get_recent_trades(%{
                 category: "spot",
                 symbol: @test_symbol_spot,
                 limit: 20
               })

      assert %{"category" => "spot", "list" => trades} = result
      assert is_list(trades)
      assert length(trades) <= 20

      if length(trades) > 0 do
        trade = hd(trades)
        assert_trade_fields(trade)
      end
    end

    @tag :integration
    test "get_recent_trades returns linear futures trades" do
      assert {:ok, result} =
               Endpoints.get_recent_trades(%{
                 category: "linear",
                 symbol: @test_symbol_linear,
                 limit: 10
               })

      assert %{"category" => "linear", "list" => trades} = result
      assert length(trades) <= 10
    end
  end

  describe "derivatives market data" do
    @tag :integration
    test "get_open_interest returns open interest data" do
      assert {:ok, result} =
               Endpoints.get_open_interest(%{
                 category: "linear",
                 symbol: @test_symbol_linear,
                 # Required parameter
                 intervalTime: "1h",
                 limit: 5
               })

      assert %{"list" => oi_list} = result
      assert is_list(oi_list)

      if length(oi_list) > 0 do
        oi = hd(oi_list)
        assert %{"openInterest" => _, "timestamp" => _} = oi
      end
    end

    @tag :integration
    test "get_funding_history returns funding rate history" do
      assert {:ok, result} =
               Endpoints.get_funding_history(%{
                 category: "linear",
                 symbol: @test_symbol_linear,
                 limit: 5
               })

      assert %{"category" => "linear", "list" => funding_list} = result
      assert is_list(funding_list)
      assert length(funding_list) <= 5

      if length(funding_list) > 0 do
        funding = hd(funding_list)
        assert %{"fundingRate" => _, "fundingRateTimestamp" => _} = funding
      end
    end
  end

  describe "instrument info endpoints" do
    @tag :integration
    test "get_instruments_info returns spot trading rules" do
      assert {:ok, result} =
               Endpoints.get_instruments_info(%{
                 category: "spot",
                 symbol: @test_symbol_spot
               })

      assert %{"category" => "spot", "list" => [instrument]} = result

      assert %{
               "symbol" => @test_symbol_spot,
               "baseCoin" => "BTC",
               "quoteCoin" => "USDT",
               "status" => status,
               "lotSizeFilter" => lot_size,
               "priceFilter" => price_filter
             } = instrument

      assert status in ["Trading", "PreLaunch"]
      assert is_map(lot_size)
      assert is_map(price_filter)
    end

    @tag :integration
    test "get_instruments_info returns all spot instruments when no symbol specified" do
      assert {:ok, result} =
               Endpoints.get_instruments_info(%{
                 category: "spot"
               })

      assert %{"category" => "spot", "list" => instruments} = result
      assert is_list(instruments)
      assert length(instruments) > 0
    end

    @tag :integration
    test "get_risk_limit returns risk limit info" do
      assert {:ok, result} =
               Endpoints.get_risk_limit(%{
                 category: "linear",
                 symbol: @test_symbol_linear
               })

      assert %{"category" => "linear", "list" => risk_limits} = result
      assert is_list(risk_limits)
    end
  end

  describe "options market data" do
    @tag :integration
    test "get_delivery_price returns options delivery price" do
      assert {:ok, result} =
               Endpoints.get_delivery_price(%{
                 category: "option",
                 baseCoin: "BTC"
               })

      assert %{"category" => "option", "list" => prices} = result
      assert is_list(prices)

      # Note: Delivery prices are typically empty unless there are recently expired options
      # Both testnet and production return empty lists when no recent deliveries
      if length(prices) > 0 do
        # Check structure of delivery price data if available
        [first | _] = prices

        assert %{
                 "deliveryPrice" => _,
                 "deliveryTime" => _,
                 "symbol" => _
               } = first
      end
    end

    @tag :integration
    test "get_historical_volatility returns volatility data" do
      assert {:ok, result} =
               Endpoints.get_historical_volatility(%{
                 category: "option",
                 baseCoin: "BTC",
                 # Add period parameter
                 period: 7
               })

      # Historical volatility returns data in the "result" key (from our curl test)
      assert is_list(result) or is_map(result)

      # Handle both response formats (list directly or wrapped in result)
      data =
        if is_map(result) and Map.has_key?(result, "result"),
          do: result["result"],
          else: result

      assert is_list(data)
      assert length(data) > 0

      # Check structure
      [first | _] = data

      assert %{
               "period" => period,
               "time" => _,
               "value" => _
             } = first

      assert period == 7
    end
  end

  describe "rate limiting" do
    @tag :integration
    test "multiple concurrent requests respect rate limits" do
      # Make 5 concurrent requests
      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            Endpoints.get_tickers(%{
              category: "spot",
              symbol: @test_symbol_spot
            })
          end)
        end

      results = Task.await_many(tasks, @timeout_ms)

      # All should succeed (rate limiter should handle it)
      for result <- results do
        assert {:ok, _} = result
      end
    end
  end

  describe "error handling" do
    @tag :integration
    test "returns error for invalid symbol" do
      assert {:error, reason} =
               Endpoints.get_tickers(%{
                 category: "spot",
                 symbol: "INVALID_SYMBOL_XYZ"
               })

      # Should get an error from Bybit
      assert reason in [
               {:invalid_request_params, "Not supported symbols"},
               {:invalid_symbol, "Not supported symbols"},
               "Not supported symbols"
             ] or match?({:invalid_request_params, _}, reason)
    end

    @tag :integration
    test "returns error for invalid category" do
      assert {:error, _reason} =
               Endpoints.get_tickers(%{
                 category: "invalid_category",
                 symbol: @test_symbol_spot
               })
    end

    @tag :integration
    test "returns error for missing required parameters" do
      # get_open_interest requires intervalTime
      assert {:error, reason} =
               Endpoints.get_open_interest(%{
                 category: "linear",
                 symbol: @test_symbol_linear
                 # Missing intervalTime
               })

      assert match?({:invalid_request_params, _}, reason)
    end
  end

  describe "module functions" do
    test "all_endpoints returns market data endpoint definitions" do
      endpoints = MarketData.all_endpoints()
      assert is_list(endpoints)
      # Based on generated file
      assert length(endpoints) == 14

      # Check structure of first endpoint
      [first | _] = endpoints

      assert %{
               operation: _,
               method: _,
               path: _,
               # Market data is public
               requires_auth: false,
               response_parser: _
             } = first
    end

    test "get_endpoint returns specific endpoint info" do
      endpoint = MarketData.get_endpoint(:get_tickers)

      assert %{
               operation: :get_tickers,
               method: :get,
               path: "/v5/market/tickers",
               requires_auth: false
             } = endpoint
    end

    test "get_endpoint returns nil for non-existent endpoint" do
      assert nil == MarketData.get_endpoint(:non_existent_endpoint)
    end
  end

  # Helper assertions
  defp assert_ticker_fields(ticker) do
    assert Map.has_key?(ticker, "symbol")
    assert Map.has_key?(ticker, "lastPrice")
    assert Map.has_key?(ticker, "bid1Price")
    assert Map.has_key?(ticker, "ask1Price")
    assert Map.has_key?(ticker, "volume24h")
    assert Map.has_key?(ticker, "turnover24h")
  end

  defp assert_trade_fields(trade) do
    assert Map.has_key?(trade, "execId")
    assert Map.has_key?(trade, "symbol")
    assert Map.has_key?(trade, "price")
    assert Map.has_key?(trade, "size")
    assert Map.has_key?(trade, "side")
    assert Map.has_key?(trade, "time")
  end
end
