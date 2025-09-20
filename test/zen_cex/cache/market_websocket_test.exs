defmodule ZenCex.Cache.MarketWebSocketTest do
  @moduledoc """
  Tests for Market cache integration with WebSocket data.

  Verifies that WebSocket data is correctly stored and retrieved
  from the ETS cache with proper TTL handling.
  """

  use ExUnit.Case, async: false

  alias ZenCex.Cache.Market

  setup do
    # Ensure cache is initialized
    Application.ensure_all_started(:zen_cex)
    :ok
  end

  describe "put_orderbook/3 with :infinity TTL" do
    test "stores orderbook data with infinite TTL" do
      orderbook = %{
        symbol: "BTCUSDT",
        update_id: 123_456,
        bids: [%{price: "50000.00", quantity: "1.5"}],
        asks: [%{price: "50001.00", quantity: "2.0"}],
        timestamp: :os.system_time(:millisecond)
      }

      assert :ok = Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      # Verify data is stored
      assert {:ok, stored} = Market.get_orderbook(:binance, "BTCUSDT")
      assert stored.symbol == "BTCUSDT"
      assert stored.update_id == 123_456
      assert length(stored.bids) == 1
      assert length(stored.asks) == 1
    end

    test "updates existing orderbook data" do
      # Store initial orderbook
      initial = %{
        symbol: "ETHUSDT",
        update_id: 1000,
        bids: [%{price: "3000.00", quantity: "10"}],
        asks: [%{price: "3001.00", quantity: "10"}],
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_orderbook(:bybit, "ETHUSDT", initial)

      # Update with new data
      updated = %{
        symbol: "ETHUSDT",
        update_id: 1001,
        bids: [%{price: "3000.50", quantity: "15"}],
        asks: [%{price: "3001.50", quantity: "15"}],
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_orderbook(:bybit, "ETHUSDT", updated)

      # Verify update
      {:ok, stored} = Market.get_orderbook(:bybit, "ETHUSDT")
      assert stored.update_id == 1001
      [bid] = stored.bids
      assert bid.price == "3000.50"
      assert bid.quantity == "15"
    end

    test "stores orderbooks for different exchanges independently" do
      binance_ob = %{
        symbol: "BTCUSDT",
        update_id: 100,
        bids: [%{price: "50000.00", quantity: "1"}],
        asks: [%{price: "50100.00", quantity: "1"}],
        timestamp: :os.system_time(:millisecond)
      }

      bybit_ob = %{
        symbol: "BTCUSDT",
        update_id: 200,
        bids: [%{price: "50010.00", quantity: "2"}],
        asks: [%{price: "50090.00", quantity: "2"}],
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_orderbook(:binance, "BTCUSDT", binance_ob)
      Market.put_orderbook(:bybit, "BTCUSDT", bybit_ob)

      # Verify independent storage
      {:ok, binance_stored} = Market.get_orderbook(:binance, "BTCUSDT")
      {:ok, bybit_stored} = Market.get_orderbook(:bybit, "BTCUSDT")

      assert binance_stored.update_id == 100
      assert bybit_stored.update_id == 200

      [binance_bid] = binance_stored.bids
      [bybit_bid] = bybit_stored.bids
      assert binance_bid.price == "50000.00"
      assert bybit_bid.price == "50010.00"
    end
  end

  describe "put_last_trade/3" do
    test "stores last trade data" do
      trade = %{
        symbol: "BTCUSDT",
        price: "50123.45",
        quantity: "0.5",
        time: 1_234_567_890,
        is_buyer_maker: true,
        timestamp: :os.system_time(:millisecond)
      }

      assert :ok = Market.put_last_trade(:binance, "BTCUSDT", trade)

      # Verify storage
      assert {:ok, stored} = Market.get_last_trade(:binance, "BTCUSDT")
      assert stored.symbol == "BTCUSDT"
      assert stored.price == "50123.45"
      assert stored.quantity == "0.5"
      assert stored.is_buyer_maker == true
    end

    test "updates with most recent trade" do
      # Store initial trade
      trade1 = %{
        symbol: "ETHUSDT",
        price: "3000.00",
        quantity: "1.0",
        time: 1000,
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_last_trade(:bybit, "ETHUSDT", trade1)

      # Update with newer trade
      trade2 = %{
        symbol: "ETHUSDT",
        price: "3001.00",
        quantity: "2.0",
        time: 1001,
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_last_trade(:bybit, "ETHUSDT", trade2)

      # Verify update
      {:ok, stored} = Market.get_last_trade(:bybit, "ETHUSDT")
      assert stored.price == "3001.00"
      assert stored.quantity == "2.0"
      assert stored.time == 1001
    end

    test "handles trade with different field names (Bybit)" do
      # Bybit uses different field names
      trade = %{
        symbol: "BTCUSDT",
        trade_id: "123456",
        price: "50000.00",
        quantity: "1.5",
        side: "Buy",
        time: 1_234_567_890,
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_last_trade(:bybit, "BTCUSDT", trade)

      {:ok, stored} = Market.get_last_trade(:bybit, "BTCUSDT")
      assert stored.price == "50000.00"
      assert stored.side == "Buy"
      assert stored.trade_id == "123456"
    end
  end

  describe "put_ticker/3 and put_ticker/4" do
    test "stores ticker with default TTL" do
      ticker = %{
        symbol: "BTCUSDT",
        last_price: "50000.00",
        open_price: "49000.00",
        high_price: "51000.00",
        low_price: "48000.00",
        volume: "1000",
        timestamp: :os.system_time(:millisecond)
      }

      assert :ok = Market.put_ticker(:binance, "BTCUSDT", ticker)

      {:ok, stored} = Market.get_ticker(:binance, "BTCUSDT")
      assert stored.last_price == "50000.00"
      assert stored.volume == "1000"
    end

    test "stores ticker with custom TTL" do
      ticker = %{
        symbol: "ETHUSDT",
        close_price: "3000.00",
        volume: "500",
        timestamp: :os.system_time(:millisecond)
      }

      # Store with 30 second TTL - the function expects TTL as a positional argument
      assert :ok = Market.put_ticker(:binance, "ETHUSDT", ticker, 30)

      # Should be retrievable immediately
      assert {:ok, _} = Market.get_ticker(:binance, "ETHUSDT")
    end

    test "handles Bybit ticker format" do
      ticker = %{
        symbol: "BTCUSDT",
        last_price: "50000.00",
        high_24h: "51000.00",
        low_24h: "49000.00",
        prev_price_24h: "49500.00",
        volume_24h: "10000",
        turnover_24h: "500000000",
        bid_price: "49999.00",
        bid_size: "10",
        ask_price: "50001.00",
        ask_size: "10",
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_ticker(:bybit, "BTCUSDT", ticker)

      {:ok, stored} = Market.get_ticker(:bybit, "BTCUSDT")
      assert stored.last_price == "50000.00"
      assert stored.high_24h == "51000.00"
      assert stored.volume_24h == "10000"
      assert stored.bid_price == "49999.00"
    end
  end

  describe "put_book_ticker/3" do
    test "stores book ticker (best bid/ask)" do
      book_ticker = %{
        symbol: "BTCUSDT",
        bid_price: "49999.50",
        bid_qty: "5.0",
        ask_price: "50000.50",
        ask_qty: "5.0",
        timestamp: :os.system_time(:millisecond)
      }

      assert :ok = Market.put_book_ticker(:binance, "BTCUSDT", book_ticker)

      {:ok, stored} = Market.get_book_ticker(:binance, "BTCUSDT")
      assert stored.bid_price == "49999.50"
      assert stored.bid_qty == "5.0"
      assert stored.ask_price == "50000.50"
      assert stored.ask_qty == "5.0"
    end

    test "updates book ticker with new values" do
      # Initial book ticker
      initial = %{
        symbol: "ETHUSDT",
        bid_price: "3000.00",
        bid_qty: "10",
        ask_price: "3001.00",
        ask_qty: "10",
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_book_ticker(:bybit, "ETHUSDT", initial)

      # Update with tighter spread
      updated = %{
        symbol: "ETHUSDT",
        bid_price: "3000.50",
        bid_qty: "15",
        ask_price: "3000.75",
        ask_qty: "15",
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_book_ticker(:bybit, "ETHUSDT", updated)

      {:ok, stored} = Market.get_book_ticker(:bybit, "ETHUSDT")
      assert stored.bid_price == "3000.50"
      assert stored.ask_price == "3000.75"
    end
  end

  describe "get_* functions with not_found handling" do
    test "returns error when orderbook not found" do
      assert {:error, :not_found} = Market.get_orderbook(:binance, "NONEXISTENT")
    end

    test "returns error when trade not found" do
      assert {:error, :not_found} = Market.get_last_trade(:binance, "NONEXISTENT")
    end

    test "returns error when ticker not found" do
      assert {:error, :not_found} = Market.get_ticker(:binance, "NONEXISTENT")
    end

    test "returns error when book ticker not found" do
      assert {:error, :not_found} = Market.get_book_ticker(:binance, "NONEXISTENT")
    end
  end

  describe "concurrent access" do
    test "handles concurrent writes to same symbol" do
      # Simulate concurrent updates from WebSocket
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            orderbook = %{
              symbol: "BTCUSDT",
              update_id: i,
              bids: [%{price: "#{50_000 + i}.00", quantity: "1"}],
              asks: [%{price: "#{50_100 + i}.00", quantity: "1"}],
              timestamp: :os.system_time(:millisecond)
            }

            Market.put_orderbook(:binance, "BTCUSDT", orderbook)
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)

      # Verify we have data (last write wins)
      assert {:ok, orderbook} = Market.get_orderbook(:binance, "BTCUSDT")
      assert is_integer(orderbook.update_id)
      assert orderbook.update_id >= 1 and orderbook.update_id <= 100
    end

    test "handles concurrent reads and writes" do
      # Start with initial data
      initial = %{
        symbol: "ETHUSDT",
        last_price: "3000.00",
        volume: "100",
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_ticker(:binance, "ETHUSDT", initial)

      # Concurrent reads and writes
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            if rem(i, 2) == 0 do
              # Write
              ticker = %{
                symbol: "ETHUSDT",
                last_price: "#{3000 + i}.00",
                volume: "#{100 + i}",
                timestamp: :os.system_time(:millisecond)
              }

              Market.put_ticker(:binance, "ETHUSDT", ticker)
            else
              # Read
              Market.get_ticker(:binance, "ETHUSDT")
            end
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All operations should complete without error
      assert Enum.all?(results, fn
               :ok -> true
               {:ok, _} -> true
               _ -> false
             end)
    end
  end

  describe "data format consistency" do
    test "preserves string prices (no conversion)" do
      # WebSocket data typically comes as strings
      orderbook = %{
        symbol: "BTCUSDT",
        update_id: 123,
        bids: [%{price: "50000.12345678", quantity: "1.23456789"}],
        asks: [%{price: "50001.87654321", quantity: "9.87654321"}],
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      {:ok, stored} = Market.get_orderbook(:binance, "BTCUSDT")
      [bid] = stored.bids
      [ask] = stored.asks

      # Prices should remain as strings
      assert bid.price == "50000.12345678"
      assert bid.quantity == "1.23456789"
      assert ask.price == "50001.87654321"
      assert ask.quantity == "9.87654321"
    end

    test "handles mixed data types in ticker" do
      # Some fields might be strings, others numbers
      ticker = %{
        symbol: "ETHUSDT",
        # String
        last_price: "3000.00",
        # String
        volume: "1000",
        # Float
        change_percent: 2.5,
        # Integer
        trade_count: 500,
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_ticker(:bybit, "ETHUSDT", ticker)

      {:ok, stored} = Market.get_ticker(:bybit, "ETHUSDT")
      assert stored.last_price == "3000.00"
      assert stored.volume == "1000"
      assert stored.change_percent == 2.5
      assert stored.trade_count == 500
    end
  end

  describe "memory and performance" do
    test "handles large orderbook efficiently" do
      # Create a large orderbook with many levels
      levels =
        for i <- 1..100 do
          %{price: "#{50_000 - i}.00", quantity: "#{i}.0"}
        end

      orderbook = %{
        symbol: "BTCUSDT",
        update_id: 999_999,
        bids: levels,
        asks: levels,
        timestamp: :os.system_time(:millisecond)
      }

      # Should store without issues
      assert :ok = Market.put_orderbook(:binance, "BTCUSDT", orderbook)

      {:ok, stored} = Market.get_orderbook(:binance, "BTCUSDT")
      assert length(stored.bids) == 100
      assert length(stored.asks) == 100
    end

    test "handles rapid updates efficiently" do
      # Simulate rapid WebSocket updates
      for i <- 1..1000 do
        trade = %{
          symbol: "BTCUSDT",
          price: "#{50_000 + rem(i, 100)}.00",
          quantity: "0.1",
          time: i,
          timestamp: :os.system_time(:millisecond)
        }

        Market.put_last_trade(:binance, "BTCUSDT", trade)
      end

      # Should have the last trade
      {:ok, last_trade} = Market.get_last_trade(:binance, "BTCUSDT")
      assert last_trade.time == 1000
    end
  end
end
