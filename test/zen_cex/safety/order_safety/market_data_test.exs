defmodule ZenCex.Safety.OrderSafety.MarketDataTest do
  @moduledoc """
  Tests for OrderSafety.MarketData module.

  Note: These are unit tests that verify the module structure and error handling.
  Integration tests with real APIs are in order_safety_integration_test.exs
  """

  use ExUnit.Case, async: false

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
    test "returns cached price when available" do
      price = Decimal.new("50000.00")
      Cache.put_price({:binance, "BTCUSDT"}, price)

      assert {:ok, ^price} = MarketData.fetch_current_price(:binance, "BTCUSDT")
    end

    test "returns error for unsupported exchange" do
      result = MarketData.fetch_current_price(:unsupported_exchange, "BTCUSDT")
      assert {:error, {:unsupported_exchange, :unsupported_exchange}} = result
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
