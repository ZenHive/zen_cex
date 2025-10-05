defmodule ZenCex.Adapters.Binance.ParserTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Parser

  # Test fixtures based on actual Binance API response formats
  @spot_balance_response %{
    "makerCommission" => 15,
    "takerCommission" => 15,
    "buyerCommission" => 0,
    "sellerCommission" => 0,
    "canTrade" => true,
    "canWithdraw" => true,
    "canDeposit" => true,
    "updateTime" => 123_456_789,
    "accountType" => "SPOT",
    "balances" => [
      %{
        "asset" => "BTC",
        "free" => "0.50000000",
        "locked" => "0.10000000"
      },
      %{
        "asset" => "USDT",
        "free" => "1000.00000000",
        "locked" => "500.00000000"
      },
      %{
        "asset" => "ETH",
        "free" => "0.00000000",
        "locked" => "0.00000000"
      }
    ]
  }

  @futures_positions_response [
    %{
      "symbol" => "BTCUSDT",
      "positionAmt" => "0.50000000",
      "entryPrice" => "50000.00000000",
      "markPrice" => "51000.00000000",
      "unRealizedProfit" => "500.00000000",
      "liquidationPrice" => "0.00000000",
      "leverage" => "10",
      "maxNotionalValue" => "5000000",
      "marginType" => "isolated",
      "isolatedMargin" => "2500.00000000",
      "isAutoAddMargin" => "false",
      "positionSide" => "LONG",
      "notional" => "25500.00000000",
      "isolatedWallet" => "2500.00000000",
      "updateTime" => 1_234_567_890
    },
    %{
      "symbol" => "ETHUSDT",
      "positionAmt" => "-2.00000000",
      "entryPrice" => "3000.00000000",
      "markPrice" => "2950.00000000",
      "unRealizedProfit" => "100.00000000",
      "liquidationPrice" => "3500.00000000",
      "leverage" => "5",
      "maxNotionalValue" => "1000000",
      "marginType" => "cross",
      "isolatedMargin" => "0.00000000",
      "isAutoAddMargin" => "false",
      "positionSide" => "SHORT",
      "notional" => "-5900.00000000",
      "isolatedWallet" => "0.00000000",
      "updateTime" => 1_234_567_891
    }
  ]

  @order_response %{
    "symbol" => "BTCUSDT",
    "orderId" => 123_456_789,
    "orderListId" => -1,
    "clientOrderId" => "test_order_123",
    "transactTime" => 1_234_567_890,
    "price" => "50000.00000000",
    "origQty" => "0.10000000",
    "executedQty" => "0.10000000",
    "cummulativeQuoteQty" => "5000.00000000",
    "status" => "FILLED",
    "timeInForce" => "GTC",
    "type" => "LIMIT",
    "side" => "BUY",
    "fills" => [
      %{
        "price" => "50000.00000000",
        "qty" => "0.10000000",
        "commission" => "0.00001000",
        "commissionAsset" => "BTC",
        "tradeId" => 987_654_321
      }
    ]
  }

  @market_order_response %{
    "symbol" => "ETHUSDT",
    "orderId" => 987_654_321,
    "clientOrderId" => "market_order_456",
    "transactTime" => 1_234_567_891,
    "price" => "0.00000000",
    "origQty" => "1.00000000",
    "executedQty" => "0.50000000",
    "status" => "PARTIALLY_FILLED",
    "type" => "MARKET",
    "side" => "SELL"
  }

  describe "parse_positions/1" do
    test "parses spot balances as positions" do
      # Returns normalized account data (map, not list)
      assert {:ok, account} = Parser.parse_positions(@spot_balance_response)

      # Raw API response with normalized keys
      assert is_map(account)
      assert account[:account_type] == "SPOT"
      assert is_list(account[:balances])
      assert length(account[:balances]) == 3

      # Check balance structure (raw API fields)
      btc_balance = Enum.find(account[:balances], &(&1[:asset] == "BTC"))
      assert btc_balance[:asset] == "BTC"
      assert btc_balance[:free] == "0.50000000"
      assert btc_balance[:locked] == "0.10000000"
      # Users calculate total: Decimal.add(free, locked)
    end

    test "parses futures positions array" do
      assert {:ok, positions} = Parser.parse_positions(@futures_positions_response)

      assert length(positions) == 2

      # Raw API fields with normalized keys
      btc_position = Enum.find(positions, &(&1[:symbol] == "BTCUSDT"))
      assert btc_position[:symbol] == "BTCUSDT"
      # Raw value, not normalized
      assert btc_position[:position_side] == "LONG"
      # String from API
      assert btc_position[:position_amt] == "0.50000000"
      assert btc_position[:entry_price] == "50000.00000000"
      assert btc_position[:mark_price] == "51000.00000000"
      assert btc_position[:un_realized_profit] == "500.00000000"
      assert btc_position[:isolated_margin] == "2500.00000000"
      assert btc_position[:update_time] == 1_234_567_890

      eth_position = Enum.find(positions, &(&1[:symbol] == "ETHUSDT"))
      assert eth_position[:symbol] == "ETHUSDT"
      # Raw value
      assert eth_position[:position_side] == "SHORT"
      # String from API
      assert eth_position[:position_amt] == "-2.00000000"
    end

    test "parses single futures position map" do
      # When given a single position map (not in array), returns map with normalized keys
      single_position = List.first(@futures_positions_response)
      assert {:ok, position} = Parser.parse_positions(single_position)

      assert is_map(position)
      assert position[:symbol] == "BTCUSDT"
      assert position[:position_side] == "LONG"
      assert position[:position_amt] == "0.50000000"
    end

    test "handles empty balances array" do
      empty_response = %{"balances" => []}
      # Returns normalized map with empty balances array
      assert {:ok, %{balances: []}} = Parser.parse_positions(empty_response)
    end

    test "handles any map format" do
      # Parser now returns ANY map with normalized keys (no format validation)
      assert {:ok, %{invalid: "format"}} = Parser.parse_positions(%{"invalid" => "format"})
    end

    test "handles invalid non-map/list formats" do
      assert {:error, :invalid_format} = Parser.parse_positions("invalid")
      assert {:error, :invalid_format} = Parser.parse_positions(nil)
    end

    test "normalizes position with invalid number values" do
      # Raw values returned as-is (no validation or conversion)
      invalid_position = %{"symbol" => "BTCUSDT", "positionAmt" => "invalid_number"}
      assert {:ok, [position]} = Parser.parse_positions([invalid_position])
      assert position[:symbol] == "BTCUSDT"
      # Returned as-is
      assert position[:position_amt] == "invalid_number"
    end
  end

  describe "parse_balances/1" do
    test "parses spot account balances" do
      assert {:ok, balances} = Parser.parse_balances(@spot_balance_response)

      assert length(balances) == 3

      btc_balance = Enum.find(balances, &(&1.asset == "BTC"))
      assert btc_balance.asset == "BTC"
      assert btc_balance.free == "0.50000000"
      assert btc_balance.locked == "0.10000000"
      # Parser returns raw API fields - users calculate total if needed

      usdt_balance = Enum.find(balances, &(&1.asset == "USDT"))
      assert usdt_balance.asset == "USDT"
      assert usdt_balance.free == "1000.00000000"
      assert usdt_balance.locked == "500.00000000"

      eth_balance = Enum.find(balances, &(&1.asset == "ETH"))
      assert eth_balance.asset == "ETH"
      assert eth_balance.free == "0.00000000"
      assert eth_balance.locked == "0.00000000"
    end

    test "handles missing balance fields with defaults" do
      response = %{
        "balances" => [
          %{"asset" => "BTC", "free" => nil, "locked" => ""},
          %{"asset" => "USDT", "free" => "100"}
          # missing locked field
        ]
      }

      assert {:ok, balances} = Parser.parse_balances(response)

      btc_balance = Enum.find(balances, &(&1.asset == "BTC"))
      assert btc_balance.free == nil
      assert btc_balance.locked == ""

      usdt_balance = Enum.find(balances, &(&1.asset == "USDT"))
      assert usdt_balance.free == "100"
      # Field doesn't exist
      assert usdt_balance[:locked] == nil
    end

    test "handles invalid format" do
      response = %{"invalid" => "format"}
      assert {:error, {:invalid_format, message}} = Parser.parse_balances(response)
      assert message =~ "Expected map with 'balances' key"
      assert message =~ ~s(%{"invalid" => "format"})
    end

    test "handles parse errors" do
      # Parser just normalizes keys - this will succeed with normalized string
      response = %{"balances" => ["invalid_balance_format"]}
      assert {:ok, ["invalid_balance_format"]} = Parser.parse_balances(response)
    end

    test "parses futures V3 balances (direct array)" do
      # Futures V3 returns array directly, not wrapped in object
      response = [
        %{
          "accountAlias" => "SgsR",
          "asset" => "USDT",
          "balance" => "122607.35137903",
          "crossWalletBalance" => "23.72469206",
          "crossUnPnl" => "0.00000000",
          "availableBalance" => "23.72469206",
          "maxWithdrawAmount" => "23.72469206",
          "marginAvailable" => true,
          "updateTime" => 1_617_939_110_373
        },
        %{
          "accountAlias" => "SgsR",
          "asset" => "BTC",
          "balance" => "1.50000000",
          "crossWalletBalance" => "1.00000000",
          "crossUnPnl" => "0.00000000",
          "availableBalance" => "1.00000000",
          "maxWithdrawAmount" => "1.00000000",
          "marginAvailable" => true,
          "updateTime" => 1_617_939_110_373
        }
      ]

      assert {:ok, balances} = Parser.parse_balances(response)
      assert length(balances) == 2

      # Parser returns raw API fields (strings), not computed fields
      usdt = Enum.find(balances, &(&1.asset == "USDT"))
      assert usdt.available_balance == "23.72469206"
      assert usdt.balance == "122607.35137903"
      assert usdt.cross_wallet_balance == "23.72469206"

      btc = Enum.find(balances, &(&1.asset == "BTC"))
      assert btc.available_balance == "1.00000000"
      assert btc.balance == "1.50000000"
      # Users calculate locked = balance - available_balance if needed
    end
  end

  describe "parse_order/1" do
    test "parses filled limit order" do
      assert {:ok, order} = Parser.parse_order(@order_response)

      assert order.order_id == 123_456_789
      assert order.client_order_id == "test_order_123"
      assert order.symbol == "BTCUSDT"
      assert order.side == :buy
      assert order.type == :limit
      assert order.price == "50000.00000000"
      assert order.orig_qty == "0.10000000"
      assert order.executed_qty == "0.10000000"
      assert order.status == :filled
      assert order.transact_time == 1_234_567_890
    end

    test "parses partially filled market order" do
      assert {:ok, order} = Parser.parse_order(@market_order_response)

      assert order.order_id == 987_654_321
      assert order.client_order_id == "market_order_456"
      assert order.symbol == "ETHUSDT"
      assert order.side == :sell
      assert order.type == :market
      assert order.price == "0.00000000"
      assert order.orig_qty == "1.00000000"
      assert order.executed_qty == "0.50000000"
      assert order.status == :partially_filled
    end

    test "handles missing optional fields" do
      minimal_order = %{
        "symbol" => "ADAUSDT",
        "orderId" => 555_555,
        "side" => "BUY",
        "type" => "MARKET",
        "status" => "NEW"
        # Missing price, quantities, timestamps, etc.
      }

      assert {:ok, order} = Parser.parse_order(minimal_order)
      assert order.symbol == "ADAUSDT"
      assert order.side == :buy
      assert order.type == :market
      assert order.status == :new
      assert order.order_id == 555_555
      # Missing fields are simply not present (no defaults)
      assert order[:price] == nil
      assert order[:orig_qty] == nil
    end

    test "handles alternative field names" do
      alt_order = %{
        "symbol" => "DOTUSDT",
        "id" => 777_777,
        "quantity" => "10",
        "side" => "SELL",
        "type" => "STOP_LOSS",
        "status" => "CANCELED",
        "time" => 1_234_567_892
      }

      assert {:ok, order} = Parser.parse_order(alt_order)
      # API uses "id", not "orderId"
      assert order.id == 777_777
      assert order.quantity == "10"
      assert order.status == :cancelled
      assert order.time == 1_234_567_892
    end

    test "normalizes order statuses" do
      statuses = [
        {"NEW", :new},
        {"PARTIALLY_FILLED", :partially_filled},
        {"FILLED", :filled},
        {"CANCELED", :cancelled},
        {"REJECTED", :rejected},
        {"EXPIRED", :expired},
        {"UNKNOWN_STATUS", :unknown}
      ]

      for {binance_status, expected_status} <- statuses do
        response = %{
          "symbol" => "TEST",
          "orderId" => 1,
          "side" => "BUY",
          "type" => "LIMIT",
          "status" => binance_status
        }

        assert {:ok, order} = Parser.parse_order(response)
        assert order.status == expected_status
      end
    end

    test "handles invalid format" do
      assert {:error, :invalid_format} = Parser.parse_order(%{"invalid" => "format"})
      assert {:error, :invalid_format} = Parser.parse_order("invalid")
      assert {:error, :invalid_format} = Parser.parse_order(nil)
    end

    test "handles parse errors" do
      # Invalid data that would cause an exception during processing
      # Must have required fields as strings to pass validation, but with data that causes errors
      invalid_order = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "status" => "NEW",
        "orderId" => "not_a_number_when_converted"
      }

      # This should still succeed as we handle conversion safely
      assert {:ok, order} = Parser.parse_order(invalid_order)
      assert order.symbol == "BTCUSDT"
    end
  end

  describe "parse_error/1" do
    test "passes through all error responses unchanged" do
      # All errors return raw response - no mapping or transformation
      error_cases = [
        %{"code" => -1121, "msg" => "Invalid symbol"},
        %{"code" => -2010, "msg" => "Account has insufficient balance"},
        %{"code" => -1013, "msg" => "Filter failure: LOT_SIZE"},
        %{"code" => 429, "msg" => "Too many requests"},
        %{"code" => -1003, "msg" => "Too many requests"},
        %{"code" => -1022, "msg" => "Signature not valid"},
        %{"code" => -2011, "msg" => "Unknown order sent"}
      ]

      for error_response <- error_cases do
        assert {:error, ^error_response} = Parser.parse_error(error_response)
      end
    end

    test "handles unknown error codes - returns raw response" do
      unknown_error = %{"code" => -9999, "msg" => "Something went wrong"}

      assert {:error, ^unknown_error} = Parser.parse_error(unknown_error)
    end

    test "handles errors without codes - returns raw response" do
      message_cases = [
        %{"msg" => "Insufficient balance for transfer"},
        %{"msg" => "Invalid symbol INVALIDPAIR"},
        %{"msg" => "Unauthorized request"},
        %{"msg" => "Some other error"}
      ]

      for error_response <- message_cases do
        assert {:error, ^error_response} = Parser.parse_error(error_response)
      end
    end

    test "handles unexpected error formats" do
      unexpected_formats = [
        %{"error" => "unexpected_format"},
        %{"random" => "data"},
        "string_error",
        nil,
        []
      ]

      for error_format <- unexpected_formats do
        result = Parser.parse_error(error_format)
        assert match?({:error, _}, result)
      end
    end
  end

  describe "parse_market_data/1" do
    test "returns not implemented error" do
      # WebSocket market data parsing is deferred to WebSocket implementation phase
      assert {:error, :not_implemented} =
               Parser.parse_market_data(%{"stream" => "btcusdt@ticker"})

      assert {:error, :not_implemented} = Parser.parse_market_data("any_data")
    end
  end

  describe "decimal conversion edge cases" do
    test "handles various numeric formats" do
      # Parser returns raw values as-is - no conversion or validation
      test_cases = [
        {"0.00000000", "0.00000000"},
        {"123.456", "123.456"},
        {"0", "0"},
        {"", ""},
        {nil, nil},
        {0, 0},
        {123.45, 123.45},
        {"invalid", "invalid"}
      ]

      # Parser just normalizes keys, returns values as-is
      for {input_value, expected_value} <- test_cases do
        response = %{"balances" => [%{"asset" => "TEST", "free" => input_value, "locked" => "0"}]}

        {:ok, [balance]} = Parser.parse_balances(response)
        assert balance.free == expected_value
      end
    end
  end

  describe "position normalization" do
    test "normalizes keys but keeps values as-is" do
      # Parser no longer normalizes enum values - returns raw API data
      position_sides = ["LONG", "SHORT", "BOTH"]

      for binance_side <- position_sides do
        position = %{
          "symbol" => "TESTUSDT",
          "positionSide" => binance_side,
          "positionAmt" => "1.0",
          "entryPrice" => "100",
          "markPrice" => "100",
          "unRealizedProfit" => "0"
        }

        assert {:ok, [parsed]} = Parser.parse_positions([position])
        # Raw value returned (not normalized to atom)
        assert parsed[:position_side] == binance_side
        assert parsed[:position_amt] == "1.0"
      end
    end
  end

  describe "parse_generic/1" do
    test "returns maps as-is" do
      response = %{"serverTime" => 1_234_567_890_000}
      assert {:ok, ^response} = Parser.parse_generic(response)
    end

    test "returns lists as-is" do
      response = [%{"orderId" => 123}, %{"orderId" => 456}]
      assert {:ok, ^response} = Parser.parse_generic(response)
    end

    test "returns empty objects as-is" do
      response = %{}
      assert {:ok, ^response} = Parser.parse_generic(response)
    end

    test "returns empty lists as-is" do
      response = []
      assert {:ok, ^response} = Parser.parse_generic(response)
    end

    test "wraps other data types in ok tuple" do
      assert {:ok, "ping"} = Parser.parse_generic("ping")
      assert {:ok, 123} = Parser.parse_generic(123)
      assert {:ok, true} = Parser.parse_generic(true)
    end
  end

  describe "parse_trades/1" do
    test "parses valid trade history" do
      response = [
        %{
          "id" => 123_456,
          "orderId" => 789,
          "symbol" => "BTCUSDT",
          "price" => "50000.00",
          "qty" => "0.1",
          "quoteQty" => "5000.00",
          "commission" => "0.001",
          "commissionAsset" => "BTC",
          "time" => 1_234_567_890_000,
          "isBuyer" => true,
          "isMaker" => false
        }
      ]

      assert {:ok, [trade]} = Parser.parse_trades(response)

      # Normalized keys (camelCase → snake_case), values as-is (strings/integers from API)
      # Integer from API
      assert trade.id == 123_456
      # Integer from API
      assert trade.order_id == 789
      assert trade.symbol == "BTCUSDT"
      # String from API
      assert trade.price == "50000.00"
      # String from API
      assert trade.qty == "0.1"
      # String from API
      assert trade.quote_qty == "5000.00"
      # String from API
      assert trade.commission == "0.001"
      assert trade.commission_asset == "BTC"
      # Integer from API
      assert trade.time == 1_234_567_890_000
      assert trade.is_buyer == true
      assert trade.is_maker == false
    end

    test "handles alternative field names" do
      response = [
        %{
          "tradeId" => 123_456,
          "quantity" => "0.1",
          "timestamp" => 1_234_567_890_000
        }
      ]

      assert {:ok, [trade]} = Parser.parse_trades(response)
      # API returns integers
      assert trade.trade_id == 123_456
      assert trade.quantity == "0.1"
      assert trade.timestamp == 1_234_567_890_000
    end

    test "handles missing fields with defaults" do
      response = [%{"symbol" => "BTCUSDT"}]

      assert {:ok, [trade]} = Parser.parse_trades(response)
      assert trade.symbol == "BTCUSDT"
      # Parser just normalizes keys - missing fields are nil
      assert trade[:trade_id] == nil
      assert trade[:order_id] == nil
      assert trade[:price] == nil
      assert trade[:is_buyer] == nil
      assert trade[:is_maker] == nil
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_trades(%{})
      assert {:error, :invalid_format} = Parser.parse_trades("invalid")
    end
  end

  describe "parse_fees/1" do
    test "parses symbol-specific commission rates (decimal strings)" do
      response = %{
        "symbol" => "BTCUSDT",
        "makerCommission" => "0.001",
        "takerCommission" => "0.0015"
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      assert fees[:symbol] == "BTCUSDT"
      # Raw values from API - users convert to Decimal if needed
      assert fees[:maker_commission] == "0.001"
      assert fees[:taker_commission] == "0.0015"
      assert fees[:buyer_commission] == nil
      assert fees[:seller_commission] == nil
    end

    test "parses account-wide commission rates (basis points)" do
      response = %{
        "makerCommission" => 10,
        "takerCommission" => 15,
        "buyerCommission" => 0,
        "sellerCommission" => 0
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      assert fees[:symbol] == nil
      # Raw integers (basis points) - users calculate: Decimal.div(value, 10000)
      assert fees[:maker_commission] == 10
      assert fees[:taker_commission] == 15
      assert fees[:buyer_commission] == 0
      assert fees[:seller_commission] == 0
    end

    test "handles mixed commission formats" do
      response = %{
        "symbol" => "ETHUSDT",
        # basis points
        "makerCommission" => 10,
        # decimal string
        "takerCommission" => "0.002"
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      assert fees[:symbol] == "ETHUSDT"
      # Raw values as-is from API
      assert fees[:maker_commission] == 10
      assert fees[:taker_commission] == "0.002"
    end

    test "handles float commission rates" do
      response = %{
        "makerCommission" => 0.001,
        "takerCommission" => 0.002
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      # Raw floats from API
      assert fees[:maker_commission] == 0.001
      assert fees[:taker_commission] == 0.002
    end

    test "normalizes all fields including extras" do
      response = %{
        "symbol" => "BTCUSDT",
        "makerCommission" => 10,
        "takerCommission" => 15,
        "extraField" => "value"
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      # All fields normalized and exposed
      assert fees[:symbol] == "BTCUSDT"
      assert fees[:maker_commission] == 10
      assert fees[:taker_commission] == 15
      assert fees[:extra_field] == "value"
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_fees([])
      assert {:error, :invalid_format} = Parser.parse_fees("invalid")
    end
  end

  describe "performance requirements" do
    test "parsing operations complete efficiently" do
      # Test parsing performance with reasonable dataset
      large_balances = %{
        "balances" =>
          for i <- 1..100 do
            %{
              "asset" => "ASSET#{i}",
              "free" => "#{i}.0",
              "locked" => "#{i * 0.1}"
            }
          end
      }

      start_time = System.monotonic_time()
      assert {:ok, balances} = Parser.parse_balances(large_balances)
      duration = System.monotonic_time() - start_time

      assert length(balances) == 100
      microseconds = System.convert_time_unit(duration, :native, :microsecond)
      assert microseconds < 10_000, "Parsing took #{microseconds}μs (should be <10ms)"
    end
  end

  describe "parse_account/1" do
    test "parses futures account information successfully" do
      response = %{
        "feeTier" => 0,
        "canTrade" => true,
        "canDeposit" => true,
        "canWithdraw" => true,
        "updateTime" => 1_234_567_890_000,
        "totalInitialMargin" => "100.00000000",
        "totalMaintMargin" => "50.00000000",
        "totalWalletBalance" => "10000.00000000",
        "totalUnrealizedProfit" => "500.00000000",
        "totalMarginBalance" => "10500.00000000",
        "totalPositionInitialMargin" => "100.00000000",
        "totalOpenOrderInitialMargin" => "0.00000000",
        "totalCrossWalletBalance" => "10000.00000000",
        "totalCrossUnPnl" => "500.00000000",
        "availableBalance" => "9900.00000000",
        "maxWithdrawAmount" => "9900.00000000",
        "assets" => [
          %{
            "asset" => "USDT",
            "walletBalance" => "10000.00000000",
            "unrealizedProfit" => "500.00000000",
            "marginBalance" => "10500.00000000",
            "maintMargin" => "50.00000000",
            "initialMargin" => "100.00000000",
            "positionInitialMargin" => "100.00000000",
            "openOrderInitialMargin" => "0.00000000",
            "maxWithdrawAmount" => "9900.00000000",
            "crossWalletBalance" => "10000.00000000",
            "crossUnPnl" => "500.00000000",
            "availableBalance" => "9900.00000000"
          }
        ],
        "positions" => [
          %{
            "symbol" => "BTCUSDT",
            "positionAmt" => "0.50000000",
            "entryPrice" => "50000.00000000",
            "markPrice" => "51000.00000000",
            "unRealizedProfit" => "500.00000000",
            "positionSide" => "LONG",
            "updateTime" => 1_234_567_890_000
          }
        ]
      }

      assert {:ok, account} = Parser.parse_account(response)

      assert account.fee_tier == 0
      assert account.can_trade == true
      assert account.can_deposit == true
      assert account.can_withdraw == true
      assert account.update_time == 1_234_567_890_000
      assert account.total_wallet_balance == "10000.00000000"
      assert account.total_unrealized_profit == "500.00000000"
      assert account.available_balance == "9900.00000000"

      assert length(account.assets) == 1
      asset = hd(account.assets)
      assert asset.asset == "USDT"
      assert asset.wallet_balance == "10000.00000000"

      assert length(account.positions) == 1
      position = hd(account.positions)
      assert position.symbol == "BTCUSDT"
      # Raw API value
      assert position.position_side == "LONG"
      assert position.position_amt == "0.50000000"
    end

    test "handles missing optional fields" do
      minimal_response = %{
        "feeTier" => 0,
        "canTrade" => true,
        "canDeposit" => true,
        "canWithdraw" => true,
        "updateTime" => 1_234_567_890_000,
        "totalInitialMargin" => "0.00000000",
        "totalMaintMargin" => "0.00000000",
        "totalWalletBalance" => "0.00000000",
        "totalUnrealizedProfit" => "0.00000000",
        "totalMarginBalance" => "0.00000000",
        "totalPositionInitialMargin" => "0.00000000",
        "totalOpenOrderInitialMargin" => "0.00000000",
        "totalCrossWalletBalance" => "0.00000000",
        "totalCrossUnPnl" => "0.00000000",
        "availableBalance" => "0.00000000",
        "maxWithdrawAmount" => "0.00000000"
      }

      assert {:ok, account} = Parser.parse_account(minimal_response)
      refute Map.has_key?(account, :assets)
      refute Map.has_key?(account, :positions)
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_account("not a map")
      assert {:error, :invalid_format} = Parser.parse_account(nil)
      assert {:error, :invalid_format} = Parser.parse_account([])
    end

    test "handles invalid decimal values gracefully" do
      invalid_response = %{
        "feeTier" => 0,
        "canTrade" => true,
        "canDeposit" => true,
        "canWithdraw" => true,
        "updateTime" => 1_234_567_890_000,
        "totalInitialMargin" => "not_a_number",
        "totalMaintMargin" => "0.00000000",
        "totalWalletBalance" => "0.00000000",
        "totalUnrealizedProfit" => "0.00000000",
        "totalMarginBalance" => "0.00000000",
        "totalPositionInitialMargin" => "0.00000000",
        "totalOpenOrderInitialMargin" => "0.00000000",
        "totalCrossWalletBalance" => "0.00000000",
        "totalCrossUnPnl" => "0.00000000",
        "availableBalance" => "0.00000000",
        "maxWithdrawAmount" => "0.00000000"
      }

      # Parser returns raw values - validation is user's responsibility
      assert {:ok, account} = Parser.parse_account(invalid_response)
      # Invalid value returned as-is
      assert account.total_initial_margin == "not_a_number"
    end
  end

  describe "parse_income/1" do
    test "parses income history records successfully" do
      response = [
        %{
          "symbol" => "BTCUSDT",
          "incomeType" => "REALIZED_PNL",
          "income" => "100.50000000",
          "asset" => "USDT",
          "time" => 1_234_567_890_000,
          "info" => "trade id 123",
          "tranId" => 987_654_321,
          "tradeId" => "123456"
        },
        %{
          "symbol" => "ETHUSDT",
          "incomeType" => "FUNDING_FEE",
          "income" => "-0.50000000",
          "asset" => "USDT",
          "time" => 1_234_567_891_000,
          "info" => "",
          "tranId" => 987_654_322,
          "tradeId" => ""
        },
        %{
          "symbol" => "BTCUSDT",
          "incomeType" => "COMMISSION",
          "income" => "-2.00000000",
          "asset" => "USDT",
          "time" => 1_234_567_892_000,
          "info" => "commission",
          "tranId" => 987_654_323,
          "tradeId" => "123457"
        }
      ]

      assert {:ok, income_records} = Parser.parse_income(response)
      assert length(income_records) == 3

      [first, second, third] = income_records

      assert first.symbol == "BTCUSDT"
      assert first.income_type == :realized_pnl
      # Parser returns strings
      assert first.income == "100.50000000"
      assert first.asset == "USDT"
      # API field is "time", not "timestamp"
      assert first.time == 1_234_567_890_000
      assert first.info == "trade id 123"
      # API field is "tranId" -> tran_id
      assert first.tran_id == 987_654_321
      assert first.trade_id == "123456"

      assert second.income_type == :funding_fee
      assert second.income == "-0.50000000"

      assert third.income_type == :commission
      assert third.income == "-2.00000000"
    end

    test "normalizes all income types correctly" do
      income_types = [
        {"TRANSFER", :transfer},
        {"WELCOME_BONUS", :welcome_bonus},
        {"REALIZED_PNL", :realized_pnl},
        {"FUNDING_FEE", :funding_fee},
        {"COMMISSION", :commission},
        {"INSURANCE_CLEAR", :insurance_clear},
        {"REFERRAL_KICKBACK", :referral_kickback},
        {"COMMISSION_REBATE", :commission_rebate},
        {"API_REBATE", :api_rebate},
        {"CONTEST_REWARD", :contest_reward},
        {"CROSS_COLLATERAL_TRANSFER", :cross_collateral_transfer},
        {"OPTIONS_PREMIUM_FEE", :options_premium_fee},
        {"OPTIONS_SETTLE_PROFIT", :options_settle_profit},
        {"INTERNAL_TRANSFER", :internal_transfer},
        {"AUTO_EXCHANGE", :auto_exchange},
        {"DELIVERED_SETTLEMENT", :delivered_settlement},
        {"COIN_SWAP_DEPOSIT", :coin_swap_deposit},
        {"COIN_SWAP_WITHDRAW", :coin_swap_withdraw},
        {"POSITION_LIMIT_INCREASE_FEE", :position_limit_increase_fee}
      ]

      for {raw_type, expected_type} <- income_types do
        response = [
          %{
            "symbol" => "BTCUSDT",
            "incomeType" => raw_type,
            "income" => "1.00000000",
            "asset" => "USDT",
            "time" => 1_234_567_890_000,
            "info" => "",
            "tranId" => 1,
            "tradeId" => ""
          }
        ]

        assert {:ok, [record]} = Parser.parse_income(response)
        assert record.income_type == expected_type
      end
    end

    test "handles unknown income types" do
      response = [
        %{
          "symbol" => "BTCUSDT",
          "incomeType" => "NEW_UNKNOWN_TYPE",
          "income" => "1.00000000",
          "asset" => "USDT",
          "time" => 1_234_567_890_000,
          "info" => "",
          "tranId" => 1,
          "tradeId" => ""
        }
      ]

      assert {:ok, [record]} = Parser.parse_income(response)
      assert record.income_type == :new_unknown_type
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_income("not a list")
      assert {:error, :invalid_format} = Parser.parse_income(nil)
      assert {:error, :invalid_format} = Parser.parse_income(%{})
    end

    test "handles invalid decimal values gracefully" do
      invalid_response = [
        %{
          "symbol" => "BTCUSDT",
          "incomeType" => "REALIZED_PNL",
          "income" => "not_a_number",
          "asset" => "USDT",
          "time" => 1_234_567_890_000,
          "info" => "",
          "tranId" => 1,
          "tradeId" => ""
        }
      ]

      # Parser returns raw values - validation/conversion is user's responsibility
      assert {:ok, [record]} = Parser.parse_income(invalid_response)
      # Raw invalid value returned as-is
      assert record.income == "not_a_number"
    end

    test "handles empty list" do
      assert {:ok, []} = Parser.parse_income([])
    end
  end
end
