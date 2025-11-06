defmodule ZenCex.Adapters.Deribit.ParserTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Deribit.Parser

  describe "parse_generic/1" do
    test "extracts result from JSON-RPC response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 123,
        "result" => %{
          "instrument_name" => "BTC-PERPETUAL",
          "last_price" => 50_000.5
        }
      }

      assert {:ok, parsed} = Parser.parse_generic(response)
      assert parsed.instrument_name == "BTC-PERPETUAL"
      assert parsed.last_price == 50_000.5
    end

    test "handles error responses" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 123,
        "error" => %{
          "code" => -32_602,
          "message" => "Invalid params"
        }
      }

      assert {:error, error} = Parser.parse_generic(response)
      assert error.error.code == -32_602
      assert error.error.message == "Invalid params"
    end

    test "normalizes camelCase keys to snake_case" do
      response = %{
        "result" => %{
          "instrumentName" => "BTC-PERPETUAL",
          "lastPrice" => 50_000.5,
          "bestBidPrice" => 49_999.0
        }
      }

      assert {:ok, parsed} = Parser.parse_generic(response)
      assert parsed.instrument_name == "BTC-PERPETUAL"
      assert parsed.last_price == 50_000.5
      assert parsed.best_bid_price == 49_999.0
    end

    test "handles pre-extracted data without result wrapper" do
      data = %{"instrument_name" => "BTC-PERPETUAL", "price" => 50_000}

      assert {:ok, parsed} = Parser.parse_generic(data)
      assert parsed.instrument_name == "BTC-PERPETUAL"
      assert parsed.price == 50_000
    end

    test "handles list results" do
      response = %{
        "result" => [
          %{"name" => "BTC"},
          %{"name" => "ETH"}
        ]
      }

      assert {:ok, parsed} = Parser.parse_generic(response)
      assert is_list(parsed)
      assert length(parsed) == 2
      assert Enum.at(parsed, 0).name == "BTC"
      assert Enum.at(parsed, 1).name == "ETH"
    end
  end

  describe "parse_order/1" do
    test "parses buy/sell response with order wrapper" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 5275,
        "result" => %{
          "trades" => [],
          "order" => %{
            "order_id" => "ETH-349253",
            "order_state" => "open",
            "order_type" => "limit",
            "direction" => "buy",
            "price" => 9000,
            "amount" => 100,
            "filled_amount" => 0,
            "instrument_name" => "BTC-PERPETUAL",
            "time_in_force" => "good_til_cancelled",
            "creation_timestamp" => 1_550_657_341_322,
            "last_update_timestamp" => 1_550_657_341_322
          }
        }
      }

      assert {:ok, parsed} = Parser.parse_order(response)
      assert parsed.order_id == "ETH-349253"
      assert parsed.order_state == :open
      assert parsed.order_type == :limit
      assert parsed.direction == :buy
      assert parsed.price == 9000
      assert parsed.amount == 100
      assert parsed.filled_amount == 0
      assert parsed.instrument_name == "BTC-PERPETUAL"
      assert parsed.time_in_force == :good_til_cancelled
    end

    test "parses cancel response without order wrapper" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 230,
        "result" => %{
          "order_id" => "ETH-349253",
          "order_state" => "cancelled",
          "direction" => "buy",
          "price" => 9000,
          "amount" => 100
        }
      }

      assert {:ok, parsed} = Parser.parse_order(response)
      assert parsed.order_id == "ETH-349253"
      assert parsed.order_state == :cancelled
      assert parsed.direction == :buy
    end

    test "normalizes order enum values" do
      order = %{
        "order_id" => "123",
        "order_state" => "filled",
        "order_type" => "market",
        "direction" => "sell",
        "time_in_force" => "immediate_or_cancel"
      }

      assert {:ok, parsed} = Parser.parse_order(order)
      assert parsed.order_state == :filled
      assert parsed.order_type == :market
      assert parsed.direction == :sell
      assert parsed.time_in_force == :immediate_or_cancel
    end

    test "handles error responses" do
      response = %{
        "error" => %{
          "code" => -32_602,
          "message" => "Invalid order_id"
        }
      }

      assert {:error, error} = Parser.parse_order(response)
      assert error.error.code == -32_602
    end
  end

  describe "parse_orders/1" do
    test "parses list of orders" do
      response = %{
        "result" => [
          %{
            "order_id" => "ETH-1",
            "order_state" => "open",
            "direction" => "buy",
            "price" => 9000
          },
          %{
            "order_id" => "ETH-2",
            "order_state" => "filled",
            "direction" => "sell",
            "price" => 11_000
          }
        ]
      }

      assert {:ok, orders} = Parser.parse_orders(response)
      assert length(orders) == 2
      assert Enum.at(orders, 0).order_id == "ETH-1"
      assert Enum.at(orders, 0).order_state == :open
      assert Enum.at(orders, 1).order_id == "ETH-2"
      assert Enum.at(orders, 1).order_state == :filled
    end

    test "handles empty order list" do
      response = %{"result" => []}

      assert {:ok, orders} = Parser.parse_orders(response)
      assert orders == []
    end
  end

  describe "parse_order_book/1" do
    test "parses order book response" do
      response = %{
        "result" => %{
          "timestamp" => 1_554_373_962_454,
          "instrument_name" => "BTC-PERPETUAL",
          "change_id" => 38_476_410,
          "bids" => [
            ["new", 5000.5, 10],
            ["change", 5000.0, 5]
          ],
          "asks" => [
            ["delete", 5001.0, 0]
          ]
        }
      }

      assert {:ok, orderbook} = Parser.parse_order_book(response)
      assert orderbook.timestamp == 1_554_373_962_454
      assert orderbook.instrument_name == "BTC-PERPETUAL"
      assert orderbook.change_id == 38_476_410
      assert is_list(orderbook.bids)
      assert is_list(orderbook.asks)
    end

    test "handles pre-extracted order book data" do
      data = %{
        "timestamp" => 1_554_373_962_454,
        "instrument_name" => "BTC-PERPETUAL",
        "bids" => [[5000.5, 10]],
        "asks" => [[5001.0, 5]]
      }

      assert {:ok, orderbook} = Parser.parse_order_book(data)
      assert orderbook.instrument_name == "BTC-PERPETUAL"
    end
  end

  describe "parse_ticker/1" do
    test "parses ticker response with all fields" do
      response = %{
        "result" => %{
          "timestamp" => 1_554_373_962_454,
          "stats" => %{
            "volume_usd" => 49.94947288,
            "volume" => 0.49355866,
            "price_change" => -0.0075,
            "low" => 10_056.5,
            "high" => 10_060.0
          },
          "state" => "open",
          "settlement_price" => 10_061.05,
          "open_interest" => 52.45271601,
          "min_price" => 10_056.5,
          "max_price" => 10_060.0,
          "mark_price" => 10_058.48,
          "last_price" => 10_058.5,
          "instrument_name" => "BTC-PERPETUAL",
          "index_price" => 10_050.2,
          "funding_8h" => 0.00001212,
          "estimated_delivery_price" => 10_050.2,
          "current_funding" => 0.00001729,
          "best_bid_price" => 10_057.0,
          "best_bid_amount" => 60_210.0,
          "best_ask_price" => 10_058.5,
          "best_ask_amount" => 53_140.0
        }
      }

      assert {:ok, ticker} = Parser.parse_ticker(response)
      assert ticker.timestamp == 1_554_373_962_454
      assert ticker.state == :open
      assert ticker.last_price == 10_058.5
      assert ticker.instrument_name == "BTC-PERPETUAL"
      assert ticker.best_bid_price == 10_057.0
      assert ticker.best_ask_price == 10_058.5
      assert is_map(ticker.stats)
      assert ticker.stats.volume == 0.49355866
    end

    test "normalizes state enum" do
      data = %{
        "timestamp" => 1_554_373_962_454,
        "state" => "closed",
        "last_price" => 10_058.5
      }

      assert {:ok, ticker} = Parser.parse_ticker(data)
      assert ticker.state == :closed
    end
  end

  describe "parse_instruments/1" do
    test "parses instruments list" do
      response = %{
        "result" => [
          %{
            "instrument_name" => "BTC-PERPETUAL",
            "kind" => "future",
            "base_currency" => "BTC",
            "quote_currency" => "USD",
            "settlement_period" => "perpetual",
            "contract_size" => 1,
            "tick_size" => 0.5
          },
          %{
            "instrument_name" => "ETH-PERPETUAL",
            "kind" => "future",
            "base_currency" => "ETH",
            "quote_currency" => "USD",
            "settlement_period" => "perpetual",
            "contract_size" => 1,
            "tick_size" => 0.05
          }
        ]
      }

      assert {:ok, instruments} = Parser.parse_instruments(response)
      assert length(instruments) == 2
      assert Enum.at(instruments, 0).instrument_name == "BTC-PERPETUAL"
      assert Enum.at(instruments, 0).kind == "future"
      assert Enum.at(instruments, 1).instrument_name == "ETH-PERPETUAL"
    end

    test "handles pre-extracted instruments list" do
      instruments = [
        %{"instrument_name" => "BTC-PERPETUAL", "kind" => "future"},
        %{"instrument_name" => "ETH-PERPETUAL", "kind" => "future"}
      ]

      assert {:ok, parsed} = Parser.parse_instruments(instruments)
      assert length(parsed) == 2
    end
  end

  describe "parse_trades/1" do
    test "parses trades from result.trades wrapper" do
      response = %{
        "result" => %{
          "trades" => [
            %{
              "trade_id" => "ETH-34066",
              "timestamp" => 1_550_657_340_846,
              "tick_direction" => 2,
              "price" => 143.81,
              "mark_price" => 143.79,
              "instrument_name" => "BTC-PERPETUAL",
              "index_price" => 143.73,
              "direction" => "buy",
              "amount" => 10
            }
          ],
          "has_more" => false
        }
      }

      assert {:ok, trades} = Parser.parse_trades(response)
      assert length(trades) == 1
      assert Enum.at(trades, 0).trade_id == "ETH-34066"
      assert Enum.at(trades, 0).direction == :buy
      assert Enum.at(trades, 0).price == 143.81
    end

    test "parses trades from direct result array" do
      response = %{
        "result" => [
          %{
            "trade_id" => "ETH-1",
            "direction" => "sell",
            "price" => 144.0,
            "amount" => 5
          }
        ]
      }

      assert {:ok, trades} = Parser.parse_trades(response)
      assert length(trades) == 1
      assert Enum.at(trades, 0).direction == :sell
    end

    test "normalizes direction enum" do
      trades = [
        %{"trade_id" => "1", "direction" => "buy", "price" => 100},
        %{"trade_id" => "2", "direction" => "sell", "price" => 101}
      ]

      assert {:ok, parsed} = Parser.parse_trades(trades)
      assert Enum.at(parsed, 0).direction == :buy
      assert Enum.at(parsed, 1).direction == :sell
    end
  end

  describe "parse_account_summary/1" do
    test "parses account summary response" do
      response = %{
        "result" => %{
          "total_pl" => 0.05,
          "session_upl" => 0.01,
          "session_rpl" => 0.04,
          "margin_balance" => 1.5,
          "maintenance_margin" => 0.2,
          "initial_margin" => 0.3,
          "available_funds" => 1.2,
          "equity" => 1.55,
          "currency" => "BTC"
        }
      }

      assert {:ok, account} = Parser.parse_account_summary(response)
      assert account.total_pl == 0.05
      assert account.margin_balance == 1.5
      assert account.equity == 1.55
      assert account.currency == "BTC"
    end
  end

  describe "parse_positions/1" do
    test "parses positions list" do
      response = %{
        "result" => [
          %{
            "instrument_name" => "BTC-PERPETUAL",
            "size" => 10,
            "direction" => "buy",
            "average_price" => 50_000,
            "mark_price" => 51_000,
            "floating_profit_loss" => 1000
          },
          %{
            "instrument_name" => "ETH-PERPETUAL",
            "size" => 100,
            "direction" => "sell",
            "average_price" => 3000,
            "mark_price" => 2950,
            "floating_profit_loss" => 500
          }
        ]
      }

      assert {:ok, positions} = Parser.parse_positions(response)
      assert length(positions) == 2
      assert Enum.at(positions, 0).instrument_name == "BTC-PERPETUAL"
      assert Enum.at(positions, 0).size == 10
      assert Enum.at(positions, 1).instrument_name == "ETH-PERPETUAL"
    end
  end

  describe "key normalization" do
    test "converts nested camelCase to snake_case" do
      response = %{
        "result" => %{
          "orderDetails" => %{
            "orderId" => "123",
            "creationTimestamp" => 1_234_567_890,
            "lastUpdateTimestamp" => 1_234_567_891
          }
        }
      }

      assert {:ok, parsed} = Parser.parse_generic(response)
      assert Map.has_key?(parsed, :order_details)
      assert parsed.order_details.order_id == "123"
      assert parsed.order_details.creation_timestamp == 1_234_567_890
      assert parsed.order_details.last_update_timestamp == 1_234_567_891
    end
  end

  describe "edge cases" do
    test "parse_generic handles invalid result types - string" do
      response = %{"result" => "unexpected_string"}
      assert {:ok, "unexpected_string"} = Parser.parse_generic(response)
    end

    test "parse_generic handles invalid result types - number" do
      response = %{"result" => 12_345}
      assert {:ok, 12_345} = Parser.parse_generic(response)
    end

    test "parse_generic handles invalid result types - boolean" do
      response = %{"result" => true}
      assert {:ok, true} = Parser.parse_generic(response)
    end

    test "parse_generic returns error for nil" do
      assert {:error, :invalid_format} = Parser.parse_generic(nil)
    end

    test "parse_generic returns error for atom" do
      assert {:error, :invalid_format} = Parser.parse_generic(:invalid)
    end

    test "parse_order handles empty string in enum field" do
      order = %{
        "order_id" => "123",
        "order_state" => "",
        "direction" => "buy"
      }

      assert {:ok, parsed} = Parser.parse_order(order)
      assert parsed.order_id == "123"
      assert parsed.order_state == :""
      assert parsed.direction == :buy
    end

    test "parse_order handles nil in enum field" do
      order = %{
        "order_id" => "123",
        "order_state" => nil,
        "direction" => "buy"
      }

      assert {:ok, parsed} = Parser.parse_order(order)
      assert parsed.order_id == "123"
      assert parsed.order_state == nil
      assert parsed.direction == :buy
    end

    test "parse_order handles integer in enum field" do
      order = %{
        "order_id" => "123",
        "order_state" => 1,
        "direction" => "buy"
      }

      assert {:ok, parsed} = Parser.parse_order(order)
      assert parsed.order_id == "123"
      assert parsed.order_state == 1
      assert parsed.direction == :buy
    end

    test "parse_order returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_order("not a map")
      assert {:error, :invalid_format} = Parser.parse_order([1, 2, 3])
      assert {:error, :invalid_format} = Parser.parse_order(123)
    end

    test "parse_orders returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_orders("not valid")
      assert {:error, :invalid_format} = Parser.parse_orders(123)
      assert {:error, :invalid_format} = Parser.parse_orders(%{"result" => "string"})
    end

    test "parse_order_book returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_order_book("not valid")
      assert {:error, :invalid_format} = Parser.parse_order_book([1, 2, 3])
      assert {:error, :invalid_format} = Parser.parse_order_book(123)
    end

    test "parse_ticker returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_ticker("not valid")
      assert {:error, :invalid_format} = Parser.parse_ticker([1, 2, 3])
      assert {:error, :invalid_format} = Parser.parse_ticker(123)
    end

    test "parse_instruments returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_instruments("not valid")
      assert {:error, :invalid_format} = Parser.parse_instruments(123)
      assert {:error, :invalid_format} = Parser.parse_instruments(%{"result" => "string"})
    end

    test "parse_trades returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_trades("not valid")
      assert {:error, :invalid_format} = Parser.parse_trades(123)
      assert {:error, :invalid_format} = Parser.parse_trades(%{"result" => "string"})
    end

    test "parse_account_summary returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_account_summary("not valid")
      assert {:error, :invalid_format} = Parser.parse_account_summary([1, 2, 3])
      assert {:error, :invalid_format} = Parser.parse_account_summary(123)
    end

    test "parse_positions returns error for invalid format" do
      assert {:error, :invalid_format} = Parser.parse_positions("not valid")
      assert {:error, :invalid_format} = Parser.parse_positions(123)
      assert {:error, :invalid_format} = Parser.parse_positions(%{"result" => "string"})
    end

    test "parse_generic handles empty map result" do
      response = %{"result" => %{}}
      assert {:ok, %{}} = Parser.parse_generic(response)
    end

    test "parse_generic handles empty list result" do
      response = %{"result" => []}
      assert {:ok, []} = Parser.parse_generic(response)
    end

    test "parse_orders handles orders with missing fields" do
      response = %{
        "result" => [
          %{"order_id" => "1"},
          %{"order_id" => "2", "direction" => "buy"}
        ]
      }

      assert {:ok, orders} = Parser.parse_orders(response)
      assert length(orders) == 2
      assert Enum.at(orders, 0).order_id == "1"
      assert Enum.at(orders, 1).order_id == "2"
      assert Enum.at(orders, 1).direction == :buy
    end

    test "error responses preserve complete structure" do
      error_response = %{
        "jsonrpc" => "2.0",
        "id" => 123,
        "error" => %{
          "code" => -32_602,
          "message" => "Invalid params",
          "data" => %{
            "reason" => "Missing required parameter",
            "param" => "instrument_name"
          }
        }
      }

      assert {:error, error} = Parser.parse_generic(error_response)
      assert error.jsonrpc == "2.0"
      assert error.id == 123
      assert error.error.code == -32_602
      assert error.error.message == "Invalid params"
      assert error.error.data.reason == "Missing required parameter"
      assert error.error.data.param == "instrument_name"
    end
  end
end
