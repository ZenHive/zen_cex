defmodule ZenCex.Adapters.Binance.MarketDataTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.MarketData

  describe "endpoint configurations" do
    test "all endpoints have required fields" do
      endpoints = MarketData.all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0

      Enum.each(endpoints, fn config ->
        assert Map.has_key?(config, :operation)
        assert Map.has_key?(config, :method)
        assert Map.has_key?(config, :path)
        assert Map.has_key?(config, :requires_auth)
        assert Map.has_key?(config, :weight)
        assert Map.has_key?(config, :timeout)
        assert Map.has_key?(config, :retry_on)
        assert Map.has_key?(config, :response_parser)
        assert Map.has_key?(config, :error_mapping)
      end)
    end

    test "spot market data endpoints" do
      # Ticker price
      config = MarketData.get_endpoint(:get_ticker_price)
      assert config.operation == :get_ticker_price
      assert config.method == :get
      assert config.path == "/api/v3/ticker/price"
      assert config.requires_auth == false
      # Weight varies based on params
      assert config.weight == 1

      # 24hr ticker
      config = MarketData.get_endpoint(:get_ticker_24hr)
      assert config.operation == :get_ticker_24hr
      assert config.method == :get
      assert config.path == "/api/v3/ticker/24hr"
      assert config.requires_auth == false

      # Order book
      config = MarketData.get_endpoint(:get_order_book)
      assert config.operation == :get_order_book
      assert config.method == :get
      assert config.path == "/api/v3/depth"
      assert config.requires_auth == false

      # Klines
      config = MarketData.get_endpoint(:get_klines)
      assert config.operation == :get_klines
      assert config.method == :get
      assert config.path == "/api/v3/klines"
      assert config.requires_auth == false

      # Exchange info
      config = MarketData.get_endpoint(:get_exchange_info)
      assert config.operation == :get_exchange_info
      assert config.method == :get
      assert config.path == "/api/v3/exchangeInfo"
      assert config.requires_auth == false
      assert config.weight == 1
    end

    test "usdm futures market data endpoints" do
      # USDM ticker price
      config = MarketData.get_endpoint(:usdm_get_ticker_price)
      assert config.operation == :usdm_get_ticker_price
      assert config.method == :get
      assert config.path == "/fapi/v1/ticker/price"
      assert config.requires_auth == false

      # USDM 24hr ticker
      config = MarketData.get_endpoint(:usdm_get_ticker_24hr)
      assert config.operation == :usdm_get_ticker_24hr
      assert config.method == :get
      assert config.path == "/fapi/v1/ticker/24hr"
      assert config.requires_auth == false

      # USDM order book
      config = MarketData.get_endpoint(:usdm_get_order_book)
      assert config.operation == :usdm_get_order_book
      assert config.method == :get
      assert config.path == "/fapi/v1/depth"
      assert config.requires_auth == false

      # USDM mark price
      config = MarketData.get_endpoint(:usdm_get_mark_price)
      assert config.operation == :usdm_get_mark_price
      assert config.method == :get
      assert config.path == "/fapi/v1/premiumIndex"
      assert config.requires_auth == false

      # USDM funding rate
      config = MarketData.get_endpoint(:usdm_get_funding_rate)
      assert config.operation == :usdm_get_funding_rate
      assert config.method == :get
      assert config.path == "/fapi/v1/fundingRate"
      assert config.requires_auth == false

      # USDM exchange info
      config = MarketData.get_endpoint(:usdm_get_exchange_info)
      assert config.operation == :usdm_get_exchange_info
      assert config.method == :get
      assert config.path == "/fapi/v1/exchangeInfo"
      assert config.requires_auth == false
    end

    test "coinm futures market data endpoints" do
      # COINM ticker price
      config = MarketData.get_endpoint(:coinm_get_ticker_price)
      assert config.operation == :coinm_get_ticker_price
      assert config.method == :get
      assert config.path == "/dapi/v1/ticker/price"
      assert config.requires_auth == false

      # COINM 24hr ticker
      config = MarketData.get_endpoint(:coinm_get_ticker_24hr)
      assert config.operation == :coinm_get_ticker_24hr
      assert config.method == :get
      assert config.path == "/dapi/v1/ticker/24hr"
      assert config.requires_auth == false

      # COINM order book
      config = MarketData.get_endpoint(:coinm_get_order_book)
      assert config.operation == :coinm_get_order_book
      assert config.method == :get
      assert config.path == "/dapi/v1/depth"
      assert config.requires_auth == false

      # COINM mark price
      config = MarketData.get_endpoint(:coinm_get_mark_price)
      assert config.operation == :coinm_get_mark_price
      assert config.method == :get
      assert config.path == "/dapi/v1/premiumIndex"
      assert config.requires_auth == false

      # COINM exchange info
      config = MarketData.get_endpoint(:coinm_get_exchange_info)
      assert config.operation == :coinm_get_exchange_info
      assert config.method == :get
      assert config.path == "/dapi/v1/exchangeInfo"
      assert config.requires_auth == false
    end

    test "all market data endpoints do not require auth" do
      endpoints = MarketData.all_endpoints()

      Enum.each(endpoints, fn config ->
        assert config.requires_auth == false,
               "Market data endpoint #{config.operation} should not require auth"
      end)
    end

    test "market data endpoints have appropriate retry settings" do
      endpoints = MarketData.all_endpoints()

      Enum.each(endpoints, fn config ->
        # Market data can be safely retried
        assert :timeout in config.retry_on
        # Note: Not all endpoints include :rate_limited or :server_error by default
      end)
    end

    test "get_weight returns correct weights" do
      # Spot endpoints
      assert MarketData.get_weight(:get_ticker_price) == 1
      assert MarketData.get_weight(:get_ticker_24hr) == 1
      assert MarketData.get_weight(:get_order_book) == 1
      assert MarketData.get_weight(:get_klines) == 1
      assert MarketData.get_weight(:get_exchange_info) == 1

      # USDM endpoints
      assert MarketData.get_weight(:usdm_get_ticker_price) == 1
      assert MarketData.get_weight(:usdm_get_ticker_24hr) == 1
      assert MarketData.get_weight(:usdm_get_order_book) == 1

      # COINM endpoints
      assert MarketData.get_weight(:coinm_get_ticker_price) == 1
      assert MarketData.get_weight(:coinm_get_ticker_24hr) == 1
      assert MarketData.get_weight(:coinm_get_order_book) == 1
    end
  end

  describe "function exports" do
    test "spot market data functions are exported" do
      exports = MarketData.__info__(:functions)

      # Spot endpoints
      assert {:get_ticker_price, 0} in exports
      assert {:get_ticker_price, 1} in exports
      assert {:get_ticker_price, 2} in exports
      assert {:get_ticker_24hr, 0} in exports
      assert {:get_ticker_24hr, 1} in exports
      assert {:get_ticker_24hr, 2} in exports
      assert {:get_order_book, 0} in exports
      assert {:get_order_book, 1} in exports
      assert {:get_order_book, 2} in exports
      assert {:get_klines, 0} in exports
      assert {:get_klines, 1} in exports
      assert {:get_klines, 2} in exports
      assert {:get_exchange_info, 0} in exports
      assert {:get_exchange_info, 1} in exports
      assert {:get_exchange_info, 2} in exports
    end

    test "usdm futures market data functions are exported" do
      exports = MarketData.__info__(:functions)

      # USDM endpoints
      assert {:usdm_get_ticker_price, 0} in exports
      assert {:usdm_get_ticker_price, 1} in exports
      assert {:usdm_get_ticker_price, 2} in exports
      assert {:usdm_get_ticker_24hr, 0} in exports
      assert {:usdm_get_ticker_24hr, 1} in exports
      assert {:usdm_get_ticker_24hr, 2} in exports
      assert {:usdm_get_order_book, 0} in exports
      assert {:usdm_get_order_book, 1} in exports
      assert {:usdm_get_order_book, 2} in exports
      assert {:usdm_get_mark_price, 0} in exports
      assert {:usdm_get_mark_price, 1} in exports
      assert {:usdm_get_mark_price, 2} in exports
      assert {:usdm_get_funding_rate, 0} in exports
      assert {:usdm_get_funding_rate, 1} in exports
      assert {:usdm_get_funding_rate, 2} in exports
    end

    test "coinm futures market data functions are exported" do
      exports = MarketData.__info__(:functions)

      # COINM endpoints
      assert {:coinm_get_ticker_price, 0} in exports
      assert {:coinm_get_ticker_price, 1} in exports
      assert {:coinm_get_ticker_price, 2} in exports
      assert {:coinm_get_ticker_24hr, 0} in exports
      assert {:coinm_get_ticker_24hr, 1} in exports
      assert {:coinm_get_ticker_24hr, 2} in exports
      assert {:coinm_get_order_book, 0} in exports
      assert {:coinm_get_order_book, 1} in exports
      assert {:coinm_get_order_book, 2} in exports
      assert {:coinm_get_mark_price, 0} in exports
      assert {:coinm_get_mark_price, 1} in exports
      assert {:coinm_get_mark_price, 2} in exports
    end
  end
end
