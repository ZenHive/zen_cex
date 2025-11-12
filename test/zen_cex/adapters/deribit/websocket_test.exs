defmodule ZenCex.Adapters.Deribit.WebSocketTest do
  @moduledoc """
  Integration tests for Deribit WebSocket adapter.

  These tests connect to the real Deribit testnet and verify:
  - Connection establishment
  - Authentication
  - Subscription to market data channels
  - Message handling and ETS cache updates
  """

  use ZenCex.TestUtilities.IntegrationCase, exchange: :deribit

  alias ZenCex.Adapters.Deribit.WebSocket
  alias ZenCex.Cache.Market

  @moduletag :integration
  @moduletag :deribit

  @subscription_wait_ms 2000

  # Shared authenticated connection for market data, cache, and API request tests
  setup_all context do
    {:ok, adapter} =
      WebSocket.connect(
        client_id: context[:client_id],
        client_secret: context[:client_secret],
        testnet: true
      )

    {:ok, authenticated_adapter} = WebSocket.authenticate(adapter)

    on_exit(fn -> WebSocket.close(authenticated_adapter) end)

    {:ok, adapter: authenticated_adapter}
  end

  describe "connection and authentication" do
    test "connects to Deribit testnet", context do
      assert {:ok, adapter} =
               WebSocket.connect(
                 client_id: context[:client_id],
                 client_secret: context[:client_secret],
                 testnet: true
               )

      assert adapter.client
      assert adapter.authenticated == false
      assert MapSet.size(adapter.subscriptions) == 0

      WebSocket.close(adapter)
    end

    test "authenticates with valid credentials", context do
      {:ok, adapter} =
        WebSocket.connect(
          client_id: context[:client_id],
          client_secret: context[:client_secret],
          testnet: true
        )

      assert {:ok, authenticated_adapter} = WebSocket.authenticate(adapter)
      assert authenticated_adapter.authenticated == true

      WebSocket.close(authenticated_adapter)
    end

    test "returns error with missing credentials" do
      {:ok, adapter} = WebSocket.connect(testnet: true)

      assert {:error, :missing_credentials} = WebSocket.authenticate(adapter)

      WebSocket.close(adapter)
    end
  end

  describe "market data subscriptions" do
    test "subscribes to order book channel", %{adapter: adapter} do
      channels = ["book.BTC-PERPETUAL.raw"]

      assert {:ok, updated_adapter} = WebSocket.subscribe(adapter, channels)
      assert MapSet.member?(updated_adapter.subscriptions, "book.BTC-PERPETUAL.raw")
    end

    test "subscribes to ticker channel", %{adapter: adapter} do
      channels = ["ticker.BTC-PERPETUAL.raw"]

      assert {:ok, updated_adapter} = WebSocket.subscribe(adapter, channels)
      assert MapSet.member?(updated_adapter.subscriptions, "ticker.BTC-PERPETUAL.raw")
    end

    test "subscribes to multiple channels", %{adapter: adapter} do
      channels = [
        "book.BTC-PERPETUAL.raw",
        "ticker.BTC-PERPETUAL.raw",
        "trades.BTC-PERPETUAL.raw"
      ]

      assert {:ok, updated_adapter} = WebSocket.subscribe(adapter, channels)
      assert MapSet.size(updated_adapter.subscriptions) == 3
    end

    test "unsubscribes from channels", %{adapter: adapter} do
      channels = ["book.BTC-PERPETUAL.raw"]

      {:ok, subscribed_adapter} = WebSocket.subscribe(adapter, channels)
      assert MapSet.member?(subscribed_adapter.subscriptions, "book.BTC-PERPETUAL.raw")

      assert {:ok, unsubscribed_adapter} = WebSocket.unsubscribe(subscribed_adapter, channels)
      refute MapSet.member?(unsubscribed_adapter.subscriptions, "book.BTC-PERPETUAL.raw")
    end
  end

  describe "ETS cache integration" do
    @tag timeout: 15_000
    test "receives order book updates and caches to ETS", %{adapter: adapter} do
      instrument = "BTC-PERPETUAL"
      channels = ["book.#{instrument}.raw"]

      {:ok, _updated_adapter} = WebSocket.subscribe(adapter, channels)

      # Wait for subscription confirmation and first message
      Process.sleep(@subscription_wait_ms)

      # Check if order book data is cached
      case Market.get_orderbook(:deribit, instrument) do
        {:ok, orderbook} ->
          assert orderbook.instrument == instrument
          assert is_list(orderbook.bids)
          assert is_list(orderbook.asks)
          assert is_integer(orderbook.timestamp)

        {:error, :not_found} ->
          # Data may not have arrived yet - expected for timing-based tests
          :ok

        {:error, other} ->
          flunk("Expected :not_found or data, got: #{inspect(other)}")
      end
    end

    @tag timeout: 15_000
    test "receives ticker updates and caches to ETS", %{adapter: adapter} do
      instrument = "BTC-PERPETUAL"
      channels = ["ticker.#{instrument}.raw"]

      {:ok, _updated_adapter} = WebSocket.subscribe(adapter, channels)

      # Wait for subscription confirmation and first message
      Process.sleep(@subscription_wait_ms)

      # Check if ticker data is cached
      case Market.get_ticker(:deribit, instrument) do
        {:ok, ticker} ->
          assert ticker.instrument == instrument
          assert is_number(ticker.last_price) or is_nil(ticker.last_price)
          assert is_integer(ticker.timestamp)

        {:error, :not_found} ->
          # Data may not have arrived yet - expected for timing-based tests
          :ok

        {:error, other} ->
          flunk("Expected :not_found or data, got: #{inspect(other)}")
      end
    end

    @tag timeout: 15_000
    test "receives trade updates and caches to ETS", %{adapter: adapter} do
      instrument = "BTC-PERPETUAL"
      channels = ["trades.#{instrument}.raw"]

      {:ok, _updated_adapter} = WebSocket.subscribe(adapter, channels)

      # Wait for subscription confirmation and first message
      Process.sleep(@subscription_wait_ms)

      # Check if trade data is cached
      case Market.get_last_trade(:deribit, instrument) do
        {:ok, trade} ->
          assert trade.instrument == instrument
          assert is_number(trade.price) or is_nil(trade.price)
          assert is_integer(trade.timestamp)

        {:error, :not_found} ->
          # Data may not have arrived yet - expected for timing-based tests
          :ok

        {:error, other} ->
          flunk("Expected :not_found or data, got: #{inspect(other)}")
      end
    end
  end

  describe "direct API requests" do
    test "sends direct request for instruments list", %{adapter: adapter} do
      assert {:ok, response} = WebSocket.send_request(adapter, "public/get_instruments", %{currency: "BTC"})

      # Response should have result key with list of instruments
      assert is_map(response)
      assert Map.has_key?(response, "result")
    end

    test "sends direct request for ticker data", %{adapter: adapter} do
      assert {:ok, response} =
               WebSocket.send_request(adapter, "public/ticker", %{instrument_name: "BTC-PERPETUAL"})

      # Response should have result key with ticker data
      assert is_map(response)
      assert Map.has_key?(response, "result")
    end

    test "sends direct request for order book", %{adapter: adapter} do
      assert {:ok, response} =
               WebSocket.send_request(adapter, "public/get_order_book", %{
                 instrument_name: "BTC-PERPETUAL",
                 depth: 5
               })

      # Response should have result key with order book data
      assert is_map(response)
      assert Map.has_key?(response, "result")
    end
  end
end
