#!/usr/bin/env elixir

# Test script for WebSocket functionality
alias ZenCex.Adapters.Binance.WebSocket, as: BinanceWS
alias ZenCex.Adapters.Bybit.WebSocket, as: BybitWS
alias ZenCex.Cache.Market

IO.puts("Testing ZenCex WebSocket Integration")
IO.puts("=====================================\n")

# Test Binance WebSocket
IO.puts("1. Testing Binance WebSocket...")
case BinanceWS.connect(testnet: false) do
  {:ok, client} ->
    IO.puts("   ✓ Connected to Binance")

    # Subscribe to streams
    :ok = BinanceWS.subscribe(client, ["btcusdt@miniTicker", "ethusdt@miniTicker"])
    IO.puts("   ✓ Subscribed to BTC and ETH tickers")

    # Wait for data
    Process.sleep(3000)

    # Check cached data
    case Market.get_ticker(:binance, "BTCUSDT") do
      {:ok, ticker} ->
        IO.puts("   ✓ BTC ticker cached: #{ticker.close_price}")
      _ ->
        IO.puts("   ⚠ No BTC ticker in cache")
    end

    case Market.get_ticker(:binance, "ETHUSDT") do
      {:ok, ticker} ->
        IO.puts("   ✓ ETH ticker cached: #{ticker.close_price}")
      _ ->
        IO.puts("   ⚠ No ETH ticker in cache")
    end

    BinanceWS.close(client)
    IO.puts("   ✓ Connection closed")

  {:error, reason} ->
    IO.puts("   ✗ Failed to connect: #{inspect(reason)}")
end

IO.puts("\n2. Testing Bybit WebSocket...")
case BybitWS.connect(testnet: false) do
  {:ok, client} ->
    IO.puts("   ✓ Connected to Bybit")

    # Subscribe to streams
    :ok = BybitWS.subscribe(client, ["tickers.BTCUSDT", "tickers.ETHUSDT"])
    IO.puts("   ✓ Subscribed to BTC and ETH tickers")

    # Wait for data
    Process.sleep(3000)

    # Check cached data
    case Market.get_ticker(:bybit, "BTCUSDT") do
      {:ok, ticker} ->
        IO.puts("   ✓ BTC ticker cached: #{ticker.last_price}")
      _ ->
        IO.puts("   ⚠ No BTC ticker in cache")
    end

    case Market.get_ticker(:bybit, "ETHUSDT") do
      {:ok, ticker} ->
        IO.puts("   ✓ ETH ticker cached: #{ticker.last_price}")
      _ ->
        IO.puts("   ⚠ No ETH ticker in cache")
    end

    BybitWS.close(client)
    IO.puts("   ✓ Connection closed")

  {:error, reason} ->
    IO.puts("   ✗ Failed to connect: #{inspect(reason)}")
end

IO.puts("\n✅ WebSocket integration test complete!")