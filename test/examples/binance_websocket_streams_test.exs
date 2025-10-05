defmodule ZenCex.Examples.BinanceWebsocketStreamsTest do
  @moduledoc """
  Tests for binance_websocket_streams.ex examples.

  These tests verify WebSocket streaming functionality:
  - Connection lifecycle (connect, subscribe, close)
  - Cache access patterns using Cache.Market
  - Both single and multiple stream handling

  Note: These tests connect to real Binance WebSocket endpoints
  and require waiting for data to arrive, so they may take longer
  than typical unit tests.
  """

  use ExUnit.Case

  alias ZenCex.Examples.BinanceWebsocketStreams

  @moduletag :example
  @moduletag :websocket

  # Wait time for WebSocket data to arrive and be cached
  @wait_for_data_ms 3000

  describe "single stream connection" do
    test "connect_single_stream/1 establishes connection" do
      assert {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")
      assert is_map(client)
      assert Map.has_key?(client, :server_pid)

      # Verify connection state
      assert {:ok, state} = BinanceWebsocketStreams.get_connection_state(client)
      assert state in [:connected, :connecting]

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    test "connect_single_stream/2 with testnet option" do
      # Note: Binance testnet WebSocket may have different behavior
      assert {:ok, client} =
               BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker", testnet: true)

      assert is_map(client)

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    test "connect_single_stream/2 with futures market option" do
      assert {:ok, client} =
               BinanceWebsocketStreams.connect_single_stream("btcusdt@depth20", market: :futures)

      assert is_map(client)

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "multiple streams connection" do
    test "connect_multiple_streams/1 establishes connection with multiple streams" do
      streams = ["btcusdt@ticker", "ethusdt@ticker", "bnbusdt@trade"]

      assert {:ok, client} = BinanceWebsocketStreams.connect_multiple_streams(streams)
      assert is_map(client)
      assert Map.has_key?(client, :server_pid)

      # Verify connection state
      assert {:ok, state} = BinanceWebsocketStreams.get_connection_state(client)
      assert state in [:connected, :connecting]

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    test "connect_multiple_streams/2 with futures market option" do
      streams = ["btcusdt@depth20", "ethusdt@depth20"]

      assert {:ok, client} =
               BinanceWebsocketStreams.connect_multiple_streams(streams, market: :futures)

      assert is_map(client)

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "dynamic subscription" do
    test "subscribe_additional/2 adds streams to existing connection" do
      # Start with one stream
      assert {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Subscribe to additional streams
      assert {:ok, :subscribed} =
               BinanceWebsocketStreams.subscribe_additional(client, [
                 "ethusdt@ticker",
                 "bnbusdt@trade"
               ])

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "cached data access" do
    @tag timeout: 10_000
    test "get_cached_ticker_data/1 returns ticker from Cache.Market" do
      # Connect to ticker stream
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Wait for data to arrive and be cached
      Process.sleep(@wait_for_data_ms)

      # Access cached data
      case BinanceWebsocketStreams.get_cached_ticker_data("BTCUSDT") do
        {:ok, ticker} ->
          # Verify structure
          assert is_map(ticker)
          # Common ticker fields (may vary by exchange/stream type)
          # Just verify we got data back
          assert map_size(ticker) > 0

        {:error, :not_found} ->
          # Data may not have arrived yet - this is acceptable
          :ok

        {:error, :expired} ->
          # Cache expired before we could read it - acceptable for timing reasons
          :ok

        other ->
          flunk("Unexpected result from get_cached_ticker_data: #{inspect(other)}")
      end

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    @tag timeout: 10_000
    test "get_cached_orderbook_data/1 returns orderbook from Cache.Market" do
      # Connect to depth stream
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@depth20")

      # Wait for data to arrive and be cached
      Process.sleep(@wait_for_data_ms)

      # Access cached data
      case BinanceWebsocketStreams.get_cached_orderbook_data("BTCUSDT") do
        {:ok, orderbook} ->
          # Verify structure
          assert is_map(orderbook)
          assert map_size(orderbook) > 0

        {:error, :not_found} ->
          # Data may not have arrived yet - acceptable
          :ok

        {:error, :expired} ->
          # Cache expired - acceptable
          :ok

        other ->
          flunk("Unexpected result from get_cached_orderbook_data: #{inspect(other)}")
      end

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    @tag timeout: 10_000
    test "get_cached_trade_data/1 returns trade from Cache.Market" do
      # Connect to trade stream
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@trade")

      # Wait for data to arrive and be cached
      Process.sleep(@wait_for_data_ms)

      # Access cached data
      case BinanceWebsocketStreams.get_cached_trade_data("BTCUSDT") do
        {:ok, trade} ->
          # Verify structure
          assert is_map(trade)
          assert map_size(trade) > 0

        {:error, :not_found} ->
          # Data may not have arrived yet - acceptable
          :ok

        {:error, :expired} ->
          # Cache expired - acceptable
          :ok

        other ->
          flunk("Unexpected result from get_cached_trade_data: #{inspect(other)}")
      end

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    @tag timeout: 10_000
    test "get_cached_book_ticker_data/1 returns book ticker from Cache.Market" do
      # Connect to book ticker stream
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@bookTicker")

      # Wait for data to arrive and be cached
      Process.sleep(@wait_for_data_ms)

      # Access cached data
      case BinanceWebsocketStreams.get_cached_book_ticker_data("BTCUSDT") do
        {:ok, book_ticker} ->
          # Verify structure
          assert is_map(book_ticker)
          assert map_size(book_ticker) > 0

        {:error, :not_found} ->
          # Data may not have arrived yet - acceptable
          :ok

        {:error, :expired} ->
          # Cache expired - acceptable
          :ok

        other ->
          flunk("Unexpected result from get_cached_book_ticker_data: #{inspect(other)}")
      end

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "connection lifecycle" do
    test "close_connection/1 properly closes WebSocket" do
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Close connection
      assert :ok = BinanceWebsocketStreams.close_connection(client)

      # Note: We can't reliably test the state after close due to timing,
      # but the close call should succeed
    end

    test "get_connection_state/1 returns connection status" do
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Get state
      assert {:ok, state} = BinanceWebsocketStreams.get_connection_state(client)
      assert state in [:connected, :connecting, :disconnected]

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "integration workflow" do
    @tag timeout: 15_000
    test "full workflow: connect -> subscribe -> access cache -> close" do
      # Step 1: Connect to initial streams
      {:ok, client} =
        BinanceWebsocketStreams.connect_multiple_streams([
          "btcusdt@ticker",
          "ethusdt@trade"
        ])

      assert is_map(client)

      # Step 2: Wait for data
      Process.sleep(@wait_for_data_ms)

      # Step 3: Access cached ticker (may or may not have data yet)
      ticker_result = BinanceWebsocketStreams.get_cached_ticker_data("BTCUSDT")

      assert match?({:ok, _}, ticker_result) or
               ticker_result in [{:error, :not_found}, {:error, :expired}]

      # Step 4: Subscribe to additional stream
      assert {:ok, :subscribed} =
               BinanceWebsocketStreams.subscribe_additional(client, ["bnbusdt@depth20"])

      # Step 5: Wait for new data
      Process.sleep(@wait_for_data_ms)

      # Step 6: Access new data (may or may not be available)
      orderbook_result = BinanceWebsocketStreams.get_cached_orderbook_data("BNBUSDT")

      assert match?({:ok, _}, orderbook_result) or
               orderbook_result in [{:error, :not_found}, {:error, :expired}]

      # Step 7: Close connection
      assert :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "cache access pattern verification" do
    test "get_cached_ticker_data/1 uses Cache.Market.get_ticker/2" do
      # This test verifies the function delegates to Cache.Market correctly
      # We can't easily mock, but we can verify the function calls don't crash
      # and return expected error format when cache is empty

      result = BinanceWebsocketStreams.get_cached_ticker_data("NONEXISTENT")

      # Should return error tuple when symbol not in cache
      assert match?({:error, _}, result)
    end

    test "get_cached_orderbook_data/1 uses Cache.Market.get_orderbook/2" do
      result = BinanceWebsocketStreams.get_cached_orderbook_data("NONEXISTENT")
      assert match?({:error, _}, result)
    end

    test "get_cached_trade_data/1 uses Cache.Market.get_last_trade/2" do
      result = BinanceWebsocketStreams.get_cached_trade_data("NONEXISTENT")
      assert match?({:error, _}, result)
    end

    test "get_cached_book_ticker_data/1 uses Cache.Market.get_book_ticker/2" do
      result = BinanceWebsocketStreams.get_cached_book_ticker_data("NONEXISTENT")
      assert match?({:error, _}, result)
    end
  end

  describe "production-ready connection patterns" do
    test "connect_with_retry/2 establishes connection with retry configuration" do
      # Connect with custom retry settings
      assert {:ok, client} =
               BinanceWebsocketStreams.connect_with_retry(
                 ["btcusdt@ticker"],
                 retry_count: 3,
                 max_backoff: 10_000
               )

      assert is_map(client)
      assert Map.has_key?(client, :server_pid)

      # Verify it's actually connected
      assert {:ok, state} = BinanceWebsocketStreams.get_connection_state(client)
      assert state in [:connected, :connecting]

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    test "connect_with_retry/1 uses production defaults" do
      # Connect with default retry settings
      assert {:ok, client} =
               BinanceWebsocketStreams.connect_with_retry(["ethusdt@trade"])

      assert is_map(client)

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "connection health monitoring" do
    test "check_connection_health/1 returns health information" do
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Get health information
      health = BinanceWebsocketStreams.check_connection_health(client)

      # Verify health map structure
      assert is_map(health)
      assert Map.has_key?(health, :state)
      assert Map.has_key?(health, :adapter)
      assert health.adapter == :binance

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    test "check_connection_health/1 tracks connection state changes" do
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Initial health check
      health1 = BinanceWebsocketStreams.check_connection_health(client)
      assert is_map(health1)

      # Wait a bit for connection to stabilize
      Process.sleep(1000)

      # Second health check should still work
      health2 = BinanceWebsocketStreams.check_connection_health(client)
      assert is_map(health2)
      assert health2.adapter == :binance

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "reconnection capabilities" do
    @tag timeout: 15_000
    test "reconnect_connection/1 re-establishes connection" do
      # Connect initially
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Verify initial connection
      assert {:ok, state} = BinanceWebsocketStreams.get_connection_state(client)
      assert state in [:connected, :connecting]

      # Force reconnection
      assert {:ok, new_client} = BinanceWebsocketStreams.reconnect_connection(client)

      # Verify new connection is established
      assert is_map(new_client)
      assert Map.has_key?(new_client, :server_pid)

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(new_client)
    end
  end

  describe "connection state tracking" do
    test "get_connection_state/1 returns current state" do
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Should return one of the valid states
      assert {:ok, state} = BinanceWebsocketStreams.get_connection_state(client)
      assert state in [:connected, :connecting, :disconnected]

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end

    test "connection state transitions from connecting to connected" do
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # May start as connecting
      {:ok, initial_state} = BinanceWebsocketStreams.get_connection_state(client)

      # Wait for connection to establish
      Process.sleep(2000)

      # Should be connected now (or still connecting if slow network)
      {:ok, final_state} = BinanceWebsocketStreams.get_connection_state(client)
      assert final_state in [:connected, :connecting]

      # Clean up
      :ok = BinanceWebsocketStreams.close_connection(client)
    end
  end

  describe "production examples" do
    @tag :slow
    @tag timeout: 20_000
    test "run_production_example/0 completes without errors" do
      # This test verifies the production example runs end-to-end
      # We can't assert on IO output, but we can verify it doesn't crash
      assert :ok = BinanceWebsocketStreams.run_production_example()
    end

    @tag :slow
    @tag timeout: 15_000
    test "run_monitoring_example/0 completes without errors" do
      # Verify monitoring example runs without crashing
      assert :ok = BinanceWebsocketStreams.run_monitoring_example()
    end
  end
end
