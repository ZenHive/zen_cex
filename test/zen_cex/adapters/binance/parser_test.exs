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
      assert {:ok, positions} = Parser.parse_positions(@spot_balance_response)

      # Should filter out zero balances (ETH) and return only BTC and USDT
      assert length(positions) == 2

      btc_position = Enum.find(positions, &(&1.symbol == "BTC"))
      assert btc_position.symbol == "BTC"
      assert btc_position.side == :long
      assert Decimal.equal?(btc_position.size, Decimal.new("0.6"))
      assert Decimal.equal?(btc_position.margin, Decimal.new("0.1"))
      assert Decimal.equal?(btc_position.entry_price, Decimal.new("0"))
      assert Decimal.equal?(btc_position.mark_price, Decimal.new("0"))
      assert Decimal.equal?(btc_position.pnl, Decimal.new("0"))

      usdt_position = Enum.find(positions, &(&1.symbol == "USDT"))
      assert usdt_position.symbol == "USDT"
      assert Decimal.equal?(usdt_position.size, Decimal.new("1500"))
      assert Decimal.equal?(usdt_position.margin, Decimal.new("500"))
    end

    test "parses futures positions array" do
      assert {:ok, positions} = Parser.parse_positions(@futures_positions_response)

      assert length(positions) == 2

      btc_position = Enum.find(positions, &(&1.symbol == "BTCUSDT"))
      assert btc_position.symbol == "BTCUSDT"
      assert btc_position.side == :long
      assert Decimal.equal?(btc_position.size, Decimal.new("0.5"))
      assert Decimal.equal?(btc_position.entry_price, Decimal.new("50000"))
      assert Decimal.equal?(btc_position.mark_price, Decimal.new("51000"))
      assert Decimal.equal?(btc_position.pnl, Decimal.new("500"))
      assert Decimal.equal?(btc_position.margin, Decimal.new("2500"))
      assert btc_position.timestamp == 1_234_567_890

      eth_position = Enum.find(positions, &(&1.symbol == "ETHUSDT"))
      assert eth_position.symbol == "ETHUSDT"
      assert eth_position.side == :short
      assert Decimal.equal?(eth_position.size, Decimal.new("-2"))
      assert Decimal.equal?(eth_position.entry_price, Decimal.new("3000"))
      assert Decimal.equal?(eth_position.mark_price, Decimal.new("2950"))
      assert Decimal.equal?(eth_position.pnl, Decimal.new("100"))
      assert Decimal.equal?(eth_position.margin, Decimal.new("0"))
    end

    test "parses single futures position" do
      single_position = List.first(@futures_positions_response)
      assert {:ok, [position]} = Parser.parse_positions(single_position)

      assert position.symbol == "BTCUSDT"
      assert position.side == :long
      assert Decimal.equal?(position.size, Decimal.new("0.5"))
    end

    test "handles empty balances array" do
      empty_response = %{"balances" => []}
      assert {:ok, []} = Parser.parse_positions(empty_response)
    end

    test "handles invalid format" do
      assert {:error, :invalid_format} = Parser.parse_positions(%{"invalid" => "format"})
      assert {:error, :invalid_format} = Parser.parse_positions("invalid")
      assert {:error, :invalid_format} = Parser.parse_positions(nil)
    end

    test "handles parse errors gracefully" do
      # Our safe_decimal function handles invalid numbers by defaulting to "0"
      invalid_position = %{"symbol" => "BTCUSDT", "positionAmt" => "invalid_number"}
      assert {:ok, [position]} = Parser.parse_positions([invalid_position])
      assert position.symbol == "BTCUSDT"
      assert Decimal.equal?(position.size, Decimal.new("0"))
    end
  end

  describe "parse_balances/1" do
    test "parses spot account balances" do
      assert {:ok, balances} = Parser.parse_balances(@spot_balance_response)

      assert length(balances) == 3

      btc_balance = Enum.find(balances, &(&1.asset == "BTC"))
      assert btc_balance.asset == "BTC"
      assert Decimal.equal?(btc_balance.free, Decimal.new("0.5"))
      assert Decimal.equal?(btc_balance.locked, Decimal.new("0.1"))
      assert Decimal.equal?(btc_balance.total, Decimal.new("0.6"))

      usdt_balance = Enum.find(balances, &(&1.asset == "USDT"))
      assert usdt_balance.asset == "USDT"
      assert Decimal.equal?(usdt_balance.free, Decimal.new("1000"))
      assert Decimal.equal?(usdt_balance.locked, Decimal.new("500"))
      assert Decimal.equal?(usdt_balance.total, Decimal.new("1500"))

      eth_balance = Enum.find(balances, &(&1.asset == "ETH"))
      assert eth_balance.asset == "ETH"
      assert Decimal.equal?(eth_balance.free, Decimal.new("0"))
      assert Decimal.equal?(eth_balance.locked, Decimal.new("0"))
      assert Decimal.equal?(eth_balance.total, Decimal.new("0"))
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
      assert Decimal.equal?(btc_balance.free, Decimal.new("0"))
      assert Decimal.equal?(btc_balance.locked, Decimal.new("0"))

      usdt_balance = Enum.find(balances, &(&1.asset == "USDT"))
      assert Decimal.equal?(usdt_balance.free, Decimal.new("100"))
      assert Decimal.equal?(usdt_balance.locked, Decimal.new("0"))
    end

    test "handles invalid format" do
      assert {:error, :invalid_format} = Parser.parse_balances(%{"invalid" => "format"})
      assert {:error, :invalid_format} = Parser.parse_balances("invalid")
    end

    test "handles parse errors" do
      # This should cause an error during Enum.map processing
      response = %{"balances" => ["invalid_balance_format"]}
      assert {:error, {:parse_error, _}} = Parser.parse_balances(response)
    end
  end

  describe "parse_order/1" do
    test "parses filled limit order" do
      assert {:ok, order} = Parser.parse_order(@order_response)

      assert order.order_id == "123456789"
      assert order.client_order_id == "test_order_123"
      assert order.symbol == "BTCUSDT"
      assert order.side == :buy
      assert order.type == :limit
      assert Decimal.equal?(order.price, Decimal.new("50000"))
      assert Decimal.equal?(order.quantity, Decimal.new("0.1"))
      assert Decimal.equal?(order.filled_quantity, Decimal.new("0.1"))
      assert order.status == :filled
      assert order.timestamp == 1_234_567_890
    end

    test "parses partially filled market order" do
      assert {:ok, order} = Parser.parse_order(@market_order_response)

      assert order.order_id == "987654321"
      assert order.client_order_id == "market_order_456"
      assert order.symbol == "ETHUSDT"
      assert order.side == :sell
      assert order.type == :market
      assert Decimal.equal?(order.price, Decimal.new("0"))
      assert Decimal.equal?(order.quantity, Decimal.new("1"))
      assert Decimal.equal?(order.filled_quantity, Decimal.new("0.5"))
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
      assert Decimal.equal?(order.price, Decimal.new("0"))
      assert Decimal.equal?(order.quantity, Decimal.new("0"))
      assert Decimal.equal?(order.filled_quantity, Decimal.new("0"))
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
      assert order.order_id == "777777"
      assert Decimal.equal?(order.quantity, Decimal.new("10"))
      assert order.status == :cancelled
      assert order.timestamp == 1_234_567_892
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
    test "parses standard Binance error codes" do
      error_cases = [
        {%{"code" => -1121, "msg" => "Invalid symbol"}, {:error, :invalid_symbol}},
        {%{"code" => -2010, "msg" => "Account has insufficient balance"}, {:error, :insufficient_balance}},
        {%{"code" => -1013, "msg" => "Invalid quantity"}, {:error, :invalid_quantity}},
        {%{"code" => 429, "msg" => "Too many requests"}, {:error, :rate_limited}},
        {%{"code" => -1022, "msg" => "Signature not valid"}, {:error, :signature_not_valid}},
        {%{"code" => -2011, "msg" => "Unknown order sent"}, {:error, :unknown_order}}
      ]

      for {error_response, expected_result} <- error_cases do
        assert Parser.parse_error(error_response) == expected_result
      end
    end

    test "handles unknown error codes with details" do
      unknown_error = %{"code" => -9999, "msg" => "Something went wrong"}

      assert {:error, {:exchange_error, "Something went wrong"}} =
               Parser.parse_error(unknown_error)
    end

    test "handles errors without codes by message content" do
      message_cases = [
        {%{"msg" => "Insufficient balance for transfer"}, {:error, :insufficient_balance}},
        {%{"msg" => "Invalid symbol INVALIDPAIR"}, {:error, :invalid_symbol}},
        {%{"msg" => "Unauthorized request"}, {:error, :invalid_credentials}},
        {%{"msg" => "Some other error"}, {:error, {:exchange_error, "Some other error"}}}
      ]

      for {error_response, expected_result} <- message_cases do
        assert Parser.parse_error(error_response) == expected_result
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
      test_cases = [
        {"0.00000000", Decimal.new("0")},
        {"123.456", Decimal.new("123.456")},
        {"0", Decimal.new("0")},
        {"", Decimal.new("0")},
        {nil, Decimal.new("0")},
        {0, Decimal.new("0")},
        {123.45, Decimal.new("123.45")},
        {"invalid", Decimal.new("0")}
      ]

      # Test through balance parsing which uses safe_decimal
      for {input_value, expected_decimal} <- test_cases do
        response = %{"balances" => [%{"asset" => "TEST", "free" => input_value, "locked" => "0"}]}

        case Parser.parse_balances(response) do
          {:ok, [balance]} ->
            assert Decimal.equal?(balance.free, expected_decimal)

          {:error, _} when input_value == "invalid" ->
            # Expected for truly invalid inputs
            :ok
        end
      end
    end
  end

  describe "position side normalization" do
    test "normalizes Binance position sides" do
      position_sides = [
        {"LONG", :long},
        {"SHORT", :short},
        {"BOTH", :long},
        {"UNKNOWN", :long}
      ]

      for {binance_side, expected_side} <- position_sides do
        position = %{
          "symbol" => "TESTUSDT",
          "positionSide" => binance_side,
          "positionAmt" => "1.0",
          "entryPrice" => "100",
          "markPrice" => "100",
          "unRealizedProfit" => "0"
        }

        assert {:ok, [parsed]} = Parser.parse_positions([position])
        assert parsed.side == expected_side
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

      assert trade.trade_id == "123456"
      assert trade.order_id == "789"
      assert trade.symbol == "BTCUSDT"
      assert Decimal.equal?(trade.price, Decimal.new("50000.00"))
      assert Decimal.equal?(trade.quantity, Decimal.new("0.1"))
      assert Decimal.equal?(trade.quote_quantity, Decimal.new("5000.00"))
      assert Decimal.equal?(trade.commission, Decimal.new("0.001"))
      assert trade.commission_asset == "BTC"
      assert trade.timestamp == 1_234_567_890_000
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
      assert trade.trade_id == "123456"
      assert Decimal.equal?(trade.quantity, Decimal.new("0.1"))
      assert trade.timestamp == 1_234_567_890_000
    end

    test "handles missing fields with defaults" do
      response = [%{"symbol" => "BTCUSDT"}]

      assert {:ok, [trade]} = Parser.parse_trades(response)
      assert trade.trade_id == ""
      assert trade.order_id == ""
      assert trade.symbol == "BTCUSDT"
      assert Decimal.equal?(trade.price, Decimal.new("0"))
      assert trade.is_buyer == false
      assert trade.is_maker == false
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
      assert fees.symbol == "BTCUSDT"
      assert Decimal.equal?(fees.maker_commission, Decimal.new("0.001"))
      assert Decimal.equal?(fees.taker_commission, Decimal.new("0.0015"))
      assert Decimal.equal?(fees.buyer_commission, Decimal.new("0"))
      assert Decimal.equal?(fees.seller_commission, Decimal.new("0"))
    end

    test "parses account-wide commission rates (basis points)" do
      response = %{
        "makerCommission" => 10,
        "takerCommission" => 15,
        "buyerCommission" => 0,
        "sellerCommission" => 0
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      assert fees.symbol == nil
      # 10 basis points = 10/10000 = 0.001
      assert Decimal.equal?(fees.maker_commission, Decimal.new("0.001"))
      # 15 basis points = 15/10000 = 0.0015
      assert Decimal.equal?(fees.taker_commission, Decimal.new("0.0015"))
      assert Decimal.equal?(fees.buyer_commission, Decimal.new("0"))
      assert Decimal.equal?(fees.seller_commission, Decimal.new("0"))
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
      assert fees.symbol == "ETHUSDT"
      assert Decimal.equal?(fees.maker_commission, Decimal.new("0.001"))
      assert Decimal.equal?(fees.taker_commission, Decimal.new("0.002"))
    end

    test "handles float commission rates" do
      response = %{
        "makerCommission" => 0.001,
        "takerCommission" => 0.002
      }

      assert {:ok, fees} = Parser.parse_fees(response)
      assert Decimal.equal?(fees.maker_commission, Decimal.new("0.001"))
      assert Decimal.equal?(fees.taker_commission, Decimal.new("0.002"))
    end

    test "handles missing fields with defaults" do
      response = %{}

      assert {:ok, fees} = Parser.parse_fees(response)
      assert fees.symbol == nil
      assert Decimal.equal?(fees.maker_commission, Decimal.new("0"))
      assert Decimal.equal?(fees.taker_commission, Decimal.new("0"))
      assert Decimal.equal?(fees.buyer_commission, Decimal.new("0"))
      assert Decimal.equal?(fees.seller_commission, Decimal.new("0"))
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
      assert Decimal.equal?(account.total_wallet_balance, Decimal.new("10000.00000000"))
      assert Decimal.equal?(account.total_unrealized_profit, Decimal.new("500.00000000"))
      assert Decimal.equal?(account.available_balance, Decimal.new("9900.00000000"))

      assert length(account.assets) == 1
      asset = hd(account.assets)
      assert asset.asset == "USDT"
      assert Decimal.equal?(asset.wallet_balance, Decimal.new("10000.00000000"))

      assert length(account.positions) == 1
      position = hd(account.positions)
      assert position.symbol == "BTCUSDT"
      assert position.side == :long
      assert Decimal.equal?(position.size, Decimal.new("0.50000000"))
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

      # safe_decimal converts invalid values to "0" rather than raising errors
      assert {:ok, account} = Parser.parse_account(invalid_response)
      assert Decimal.equal?(account.total_initial_margin, Decimal.new("0"))
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
      assert Decimal.equal?(first.income, Decimal.new("100.50000000"))
      assert first.asset == "USDT"
      assert first.timestamp == 1_234_567_890_000
      assert first.info == "trade id 123"
      assert first.transaction_id == 987_654_321
      assert first.trade_id == "123456"

      assert second.income_type == :funding_fee
      assert Decimal.equal?(second.income, Decimal.new("-0.50000000"))

      assert third.income_type == :commission
      assert Decimal.equal?(third.income, Decimal.new("-2.00000000"))
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

      # safe_decimal converts invalid values to "0" rather than raising errors
      assert {:ok, [record]} = Parser.parse_income(invalid_response)
      assert Decimal.equal?(record.income, Decimal.new("0"))
    end

    test "handles empty list" do
      assert {:ok, []} = Parser.parse_income([])
    end
  end
end
