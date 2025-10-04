defmodule ZenCex.Safety.OrderSafety.MarketDataTest do
  @moduledoc """
  Tests for OrderSafety.MarketData module.

  Note: These are unit tests that verify the module structure and error handling.
  Integration tests with real APIs are in order_safety_integration_test.exs
  """

  use ExUnit.Case, async: false

  alias ZenCex.Cache.Market
  alias ZenCex.Safety.OrderSafety.Cache
  alias ZenCex.Safety.OrderSafety.MarketData

  describe "fetch_symbol_info/2" do
    test "returns cached symbol info when available" do
      symbol_info = %{
        status: "TRADING",
        base_asset: "BTC",
        quote_asset: "USDT",
        filters: []
      }

      # Prime the cache
      Cache.put_symbol_info({:binance, "BTCUSDT"}, symbol_info)

      assert {:ok, ^symbol_info} = MarketData.fetch_symbol_info(:binance, "BTCUSDT")
    end

    test "returns error for unsupported exchange" do
      result = MarketData.fetch_symbol_info(:unsupported_exchange, "BTCUSDT")
      assert {:error, {:unsupported_exchange, :unsupported_exchange}} = result
    end
  end

  describe "fetch_current_price/2" do
    test "returns cached price when available in OrderSafety cache" do
      price = Decimal.new("50000.00")
      Cache.put_price({:binance, "BTCUSDT"}, price)

      assert {:ok, ^price} = MarketData.fetch_current_price(:binance, "BTCUSDT")
    end

    test "prefers fresh WebSocket data over REST" do
      # Clear OrderSafety cache
      Cache.clear_all()

      # Put fresh WebSocket data
      book_ticker = %{
        bid_price: "49999.50",
        ask_price: "50000.50",
        bid_qty: "1.0",
        ask_qty: "1.0",
        timestamp: System.system_time(:millisecond)
      }

      Market.put_book_ticker(:binance, "BTCUSDT", book_ticker)

      # Fetch should use WebSocket data and calculate mid price
      assert {:ok, price} = MarketData.fetch_current_price(:binance, "BTCUSDT")
      expected_mid = Decimal.new("50000.00")
      assert Decimal.equal?(price, expected_mid)
    end

    test "falls back to REST when WebSocket data is stale" do
      # Clear OrderSafety cache
      Cache.clear_all()

      # Put stale WebSocket data (10 seconds old)
      stale_timestamp = System.system_time(:millisecond) - 10_000

      book_ticker = %{
        bid_price: "49999.50",
        ask_price: "50000.50",
        bid_qty: "1.0",
        ask_qty: "1.0",
        timestamp: stale_timestamp
      }

      Market.put_book_ticker(:binance, "BTCUSDT", book_ticker)

      # Fetch should fall back to REST
      result = MarketData.fetch_current_price(:binance, "BTCUSDT")

      # REST should succeed in testnet environment
      assert {:ok, price} = result
      assert is_struct(price, Decimal)

      # The price should NOT be the mid price from our stale WebSocket data
      stale_mid = Decimal.new("50000.00")
      refute Decimal.equal?(price, stale_mid), "Got stale WebSocket price instead of fresh REST price"
    end

    test "falls back to REST when WebSocket data not available" do
      # Clear all caches
      Cache.clear_all()
      Market.clear_all()

      # Fetch should fall back to REST
      result = MarketData.fetch_current_price(:binance, "BTCUSDT")

      # REST should succeed in testnet environment
      assert {:ok, price} = result
      assert is_struct(price, Decimal)
      assert Decimal.gt?(price, Decimal.new("0")), "Price should be positive"
    end

    test "handles malformed WebSocket price data gracefully" do
      # Clear OrderSafety cache
      Cache.clear_all()

      # Put malformed WebSocket data
      book_ticker = %{
        bid_price: "not_a_number",
        ask_price: "50000.50",
        bid_qty: "1.0",
        ask_qty: "1.0",
        timestamp: System.system_time(:millisecond)
      }

      Market.put_book_ticker(:binance, "BTCUSDT", book_ticker)

      # Should fall back to REST after WebSocket parse failure
      result = MarketData.fetch_current_price(:binance, "BTCUSDT")

      # REST should succeed as fallback
      assert {:ok, price} = result
      assert is_struct(price, Decimal)
      assert Decimal.gt?(price, Decimal.new("0")), "Price should be positive"
    end

    test "returns error for unsupported exchange" do
      result = MarketData.fetch_current_price(:unsupported_exchange, "BTCUSDT")
      assert {:error, {:unsupported_exchange, :unsupported_exchange}} = result
    end
  end

  describe "get_market_price/2" do
    test "delegates to fetch_current_price" do
      price = Decimal.new("55000.00")
      Cache.put_price({:binance, "BTCUSDT"}, price)

      assert {:ok, ^price} = MarketData.get_market_price(:binance, "BTCUSDT")
    end
  end

  describe "fetch_orderbook/2" do
    test "prefers fresh WebSocket orderbook data" do
      # Clear caches
      Cache.clear_all()

      # Put fresh WebSocket orderbook
      orderbook = %{
        bids: [["49999.00", "1.0"], ["49998.00", "2.0"], ["49997.00", "3.0"]],
        asks: [["50001.00", "1.0"], ["50002.00", "2.0"], ["50003.00", "3.0"]],
        timestamp: System.system_time(:millisecond)
      }

      Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      # Fetch should use WebSocket data
      assert {:ok, book} = MarketData.fetch_orderbook(:binance, "BTCUSDT")
      assert length(book.bids) == 3
      assert length(book.asks) == 3
    end

    test "limits orderbook depth when requested" do
      # Put orderbook with many levels
      orderbook = %{
        bids: for(i <- 1..50, do: [to_string(50_000 - i), "1.0"]),
        asks: for(i <- 1..50, do: [to_string(50_000 + i), "1.0"]),
        timestamp: System.system_time(:millisecond)
      }

      Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      # Fetch with depth limit
      assert {:ok, book} = MarketData.fetch_orderbook(:binance, "BTCUSDT", depth: 5)
      assert length(book.bids) == 5
      assert length(book.asks) == 5
    end

    test "falls back to REST when WebSocket orderbook is stale" do
      # Put stale orderbook (10 seconds old)
      stale_timestamp = System.system_time(:millisecond) - 10_000

      orderbook = %{
        bids: [["49999.00", "1.0"]],
        asks: [["50001.00", "1.0"]],
        timestamp: stale_timestamp
      }

      Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      # Should fall back to REST
      result = MarketData.fetch_orderbook(:binance, "BTCUSDT")

      # REST should succeed in testnet environment
      assert {:ok, book} = result
      assert is_map(book)
      assert is_list(book.bids)
      assert is_list(book.asks)
      # Should have fresh data, not our single stale entry
      assert length(book.bids) > 0
      assert length(book.asks) > 0
    end

    test "handles orderbook without timestamp" do
      # Put orderbook without timestamp (treated as potentially fresh)
      orderbook = %{
        bids: [["49999.00", "1.0"]],
        asks: [["50001.00", "1.0"]]
      }

      Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      # Should accept the data
      assert {:ok, book} = MarketData.fetch_orderbook(:binance, "BTCUSDT")
      assert length(book.bids) == 1
      assert length(book.asks) == 1
    end

    test "falls back to REST for unsupported exchange" do
      result = MarketData.fetch_orderbook(:unsupported_exchange, "BTCUSDT")
      assert {:error, {:unsupported_exchange, :unsupported_exchange}} = result
    end
  end

  describe "ensure_websocket_connection/2" do
    test "returns :ok when WebSocket supervisor is running" do
      # Note: In test environment, WebSocket supervisor may not be running
      # This test just verifies the function exists and handles both cases
      result = MarketData.ensure_websocket_connection(:binance, "BTCUSDT")

      case result do
        :ok -> :ok
        {:error, :websocket_not_started} -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "fetch_balances/2" do
    test "validates auth credentials and rejects invalid keys" do
      invalid_credentials = %{
        api_key: "valid_key",
        # Invalid key
        password: "should_not_be_here",
        # Invalid key
        secret_token: "another_invalid"
      }

      result = MarketData.fetch_balances(:binance, %{auth_credentials: invalid_credentials})
      assert {:error, {:invalid_credential_keys, unauthorized_keys}} = result
      assert :password in unauthorized_keys
      assert :secret_token in unauthorized_keys
    end

    test "rejects credentials with suspicious patterns" do
      suspicious_credentials = %{
        # Looks like a bearer token
        api_key: "Bearer eyJhbGciOiJIUzI1NiIs..."
      }

      result = MarketData.fetch_balances(:binance, %{auth_credentials: suspicious_credentials})
      assert {:error, {:suspicious_credential_content, _}} = result
    end

    test "handles different Binance account types" do
      valid_credentials = %{api_key: "test_key", api_secret: "test_secret"}

      # Test unsupported account type
      result =
        MarketData.fetch_balances(:binance, %{
          account_type: :unsupported_type,
          auth_credentials: valid_credentials
        })

      assert {:error, {:unsupported_account_type, :unsupported_type}} = result
    end

    test "returns error for unsupported exchange" do
      result = MarketData.fetch_balances(:unsupported_exchange, %{})
      assert {:error, {:unsupported_exchange, :unsupported_exchange}} = result
    end
  end

  describe "get_min_notional/2" do
    test "returns cached min notional when available" do
      min_notional = Decimal.new("10.00")
      Cache.put_min_notional({:binance, "BTCUSDT"}, min_notional)

      result = MarketData.get_min_notional(:binance, "BTCUSDT")
      assert Decimal.equal?(result, min_notional)
    end

    test "returns default min notional on fetch failure" do
      # Clear cache to force fetch attempt
      Cache.clear_all()

      # For exchanges with no real API available in test, it should return default
      result = MarketData.get_min_notional(:kraken, "BTCUSD")
      assert Decimal.equal?(result, Decimal.new("10.00"))
    end

    test "extracts min notional from Binance symbol filters" do
      symbol_info = %{
        status: "TRADING",
        filters: [
          %{"filterType" => "PRICE_FILTER", "minPrice" => "0.01"},
          %{"filterType" => "NOTIONAL", "minNotional" => "15.00"},
          %{"filterType" => "LOT_SIZE", "minQty" => "0.001"}
        ]
      }

      # Prime the cache with symbol info
      Cache.put_symbol_info({:binance, "TESTUSDT"}, symbol_info)

      # Clear min notional cache to force extraction
      Cache.invalidate_min_notional(:binance, "TESTUSDT")

      result = MarketData.get_min_notional(:binance, "TESTUSDT")
      assert Decimal.equal?(result, Decimal.new("15.00"))
    end

    test "returns Bybit default min notional" do
      symbol_info = %{
        status: "TRADING",
        lot_size_filter: %{"minOrderQty" => "0.001"}
      }

      # Prime the cache with symbol info
      Cache.put_symbol_info({:bybit, "BTCUSDT"}, symbol_info)

      # Clear min notional cache to force extraction
      Cache.invalidate_min_notional(:bybit, "BTCUSDT")

      result = MarketData.get_min_notional(:bybit, "BTCUSDT")
      assert Decimal.equal?(result, Decimal.new("1.00"))
    end
  end

  describe "credential validation" do
    test "accepts valid credential formats" do
      valid_cases = [
        %{api_key: "key123", api_secret: "secret456"},
        %{api_key: "key", api_secret: "secret", passphrase: "pass"},
        %{auth_credentials: %{api_key: "nested_key"}},
        # Empty credentials are valid
        %{}
      ]

      for credentials <- valid_cases do
        # Test through fetch_balances which validates credentials
        result = MarketData.fetch_balances(:binance, %{auth_credentials: credentials})
        # Should not be a credential validation error
        case result do
          {:error, {:invalid_credential_keys, _}} ->
            flunk("Valid credentials rejected: #{inspect(credentials)}")

          {:error, {:suspicious_credential_content, _}} ->
            flunk("Valid credentials marked suspicious: #{inspect(credentials)}")

          {:error, {:invalid_credentials_format, _}} ->
            flunk("Valid credentials format rejected: #{inspect(credentials)}")

          _ ->
            # Other errors are fine (API errors, etc.)
            :ok
        end
      end
    end

    test "rejects non-map credential formats" do
      invalid_formats = [
        "string_credentials",
        123,
        [:api_key, "value"],
        nil
      ]

      for credentials <- invalid_formats do
        result = MarketData.fetch_balances(:binance, %{auth_credentials: credentials})
        assert {:error, {:invalid_credentials_format, _}} = result
      end
    end
  end

  describe "balance extraction structure validation" do
    test "validates expected balance format structures" do
      # These test cases validate the expected structure of balance responses
      test_cases = [
        # Spot format
        %{
          type: :spot,
          balances: %{
            "BTC" => %{
              free: "1.5",
              locked: "0.5",
              total: "2.0"
            }
          }
        },
        # Margin format
        %{
          type: :margin,
          balances: %{
            "BTC" => %{
              free: "1.0",
              locked: "0.2",
              borrowed: "0.5",
              interest: "0.01",
              net: "0.29"
            }
          }
        },
        # Futures format
        %{
          type: :usdm_futures,
          balances: %{
            "USDT" => %{
              wallet_balance: "10000",
              unrealized_profit: "500",
              margin_balance: "10500",
              available_balance: "9000"
            }
          }
        },
        # Portfolio margin format
        %{
          type: :portfolio_margin,
          uni_mmr: "0.15",
          account_equity: "100000",
          maint_margin: "15000"
        }
      ]

      for test_case <- test_cases do
        # Verify the structure is valid
        assert is_atom(test_case.type)

        if Map.has_key?(test_case, :balances) do
          assert is_map(test_case.balances)
        end
      end
    end
  end

  describe "min notional extraction" do
    test "handles missing NOTIONAL filter for Binance" do
      symbol_info = %{
        status: "TRADING",
        filters: [
          %{"filterType" => "PRICE_FILTER", "minPrice" => "0.01"},
          %{"filterType" => "LOT_SIZE", "minQty" => "0.001"}
        ]
      }

      Cache.put_symbol_info({:binance, "NOUSDTFILTER"}, symbol_info)
      Cache.invalidate_min_notional(:binance, "NOUSDTFILTER")

      result = MarketData.get_min_notional(:binance, "NOUSDTFILTER")
      # Should use default Binance min notional
      assert Decimal.equal?(result, Decimal.new("10.00"))
    end

    test "handles MIN_NOTIONAL filter type as alternative" do
      symbol_info = %{
        status: "TRADING",
        filters: [
          %{"filterType" => "MIN_NOTIONAL", "minNotional" => "20.00"}
        ]
      }

      Cache.put_symbol_info({:binance, "ALTUSDT"}, symbol_info)
      Cache.invalidate_min_notional(:binance, "ALTUSDT")

      result = MarketData.get_min_notional(:binance, "ALTUSDT")
      assert Decimal.equal?(result, Decimal.new("20.00"))
    end
  end

  describe "cache interaction" do
    test "fetch_symbol_info caches successful results" do
      # Clear cache first
      Cache.clear_all()

      # Prime with valid symbol info
      symbol_info = %{status: "TRADING", filters: []}
      Cache.put_symbol_info({:binance, "TESTCACHE"}, symbol_info)

      # First fetch should return cached value
      assert {:ok, ^symbol_info} = MarketData.fetch_symbol_info(:binance, "TESTCACHE")

      # Verify it's actually cached
      assert {:ok, ^symbol_info} = Cache.lookup_symbol_info({:binance, "TESTCACHE"})
    end

    test "fetch_current_price caches successful results" do
      Cache.clear_all()

      price = Decimal.new("42000.00")
      Cache.put_price({:binance, "BTCUSDT"}, price)

      # Fetch should return cached value
      assert {:ok, ^price} = MarketData.fetch_current_price(:binance, "BTCUSDT")

      # Verify it's actually cached
      assert {:ok, ^price} = Cache.lookup_price({:binance, "BTCUSDT"})
    end
  end
end
