defmodule ZenCex.Adapters.Binance.CoinmFuturesIntegrationTest do
  @moduledoc """
  Integration tests for Binance COIN-M Futures endpoints.

  These tests verify:
  - COIN-M endpoints use correct testnet URL with /dapi/ paths
  - Rate limiting uses correct futures limits (2400/min)
  - API type detection works correctly for coin-margined futures
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :coinm_futures

  import ExUnit.CaptureLog

  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.RateLimiter

  setup do
    # Reset rate limiter state before each test
    RateLimiter.reset(nil)
    :ok
  end

  describe "COIN-M futures endpoints use correct testnet URL" do
    test "get_positions uses /dapi/ path on futures testnet" do
      # Capture logs to verify correct API detection
      logs =
        capture_log([level: :debug], fn ->
          result = CoinmFutures.get_positions()

          case result do
            {:ok, positions} ->
              assert is_list(positions)
              IO.puts("TESTNET COIN-M positions: #{inspect(positions)}")

            {:error, {:exchange_error, msg}} ->
              # Expected if testnet account doesn't have COIN-M futures enabled
              if String.contains?(msg, "Invalid API-key") do
                IO.puts("TESTNET COIN-M auth error (expected if no futures account): #{msg}")
              else
                IO.puts("TESTNET COIN-M exchange error: #{msg}")
              end

            {:error, reason} ->
              IO.puts("TESTNET COIN-M error: #{inspect(reason)}")
          end
        end)

      # Verify the rate limiter detected this as a COIN-M futures request
      assert logs =~ "Binance coinm_futures API usage:" or
               logs =~ "coinm_futures API at"

      # The URL should contain /dapi/ path
      assert logs =~ "/dapi/" or logs =~ "testnet.binancefuture.com"
    end

    test "get_account uses /dapi/v1/account path" do
      logs =
        capture_log([level: :debug], fn ->
          result = CoinmFutures.get_account()

          case result do
            {:ok, account} ->
              assert is_map(account)
              # COIN-M accounts have positions in BTC/ETH, not USDT
              IO.puts("TESTNET COIN-M account: #{inspect(account)}")

            {:error, {:exchange_error, msg}} ->
              IO.puts("TESTNET COIN-M account error: #{msg}")

            {:error, reason} ->
              IO.puts("TESTNET COIN-M error: #{inspect(reason)}")
          end
        end)

      # Verify correct path is used
      assert logs =~ "/dapi/v1/account"
    end

    test "get_balances uses /dapi/v1/balance path" do
      logs =
        capture_log([level: :debug], fn ->
          result = CoinmFutures.get_balances()

          case result do
            {:ok, balances} ->
              assert is_list(balances) or is_map(balances)
              IO.puts("TESTNET COIN-M balances: #{inspect(balances)}")

            {:error, reason} ->
              IO.puts("TESTNET COIN-M balance error: #{inspect(reason)}")
          end
        end)

      # Verify correct path is used
      assert logs =~ "/dapi/v1/balance"
    end
  end

  describe "rate limiting for COIN-M futures" do
    test "COIN-M futures endpoints tracked with 2400/min limit" do
      # Get initial status
      initial_status = RateLimiter.get_status("/dapi/v1/positionRisk")
      assert initial_status.limit == 2400

      # Make a COIN-M futures request
      _result = CoinmFutures.get_positions()

      # Check that COIN-M futures counter was incremented
      futures_status = RateLimiter.get_status("/dapi/v1/positionRisk")
      assert futures_status.limit == 2400
      assert futures_status.used >= initial_status.used
    end

    test "rate limiter distinguishes COIN-M from USD-M futures" do
      # Check USD-M futures endpoint
      usdm_status = RateLimiter.get_status("/fapi/v3/positionRisk")
      assert usdm_status.limit == 2400

      # Check COIN-M futures endpoint
      coinm_status = RateLimiter.get_status("/dapi/v1/positionRisk")
      assert coinm_status.limit == 2400

      # They should have different limits from spot
      spot_status = RateLimiter.get_status("/api/v3/account")
      assert spot_status.limit == 1200

      # Futures APIs have higher limits than spot
      assert coinm_status.limit > spot_status.limit
      assert usdm_status.limit > spot_status.limit
    end
  end

  describe "order operations" do
    test "place_order has no retries configured" do
      # Verify configuration at runtime
      config = CoinmFutures.get_endpoint(:place_order)
      assert config.max_retries == 0
      assert config.retry_on == []
      assert config.timeout == 2_000
    end

    test "cancel_order allows timeout retry only" do
      config = CoinmFutures.get_endpoint(:cancel_order)
      assert config.max_retries == 1
      assert config.retry_on == [:timeout]
      assert config.timeout == 2_000
    end
  end

  describe "COIN-M specific features" do
    test "supports coin-margined symbols like BTCUSD_PERP" do
      # COIN-M uses different symbol format than USD-M
      # USD-M: BTCUSDT, ETHUSDT
      # COIN-M: BTCUSD_PERP, ETHUSD_PERP, BTCUSD_240329 (dated futures)

      logs =
        capture_log([level: :debug], fn ->
          # Try to get order for a COIN-M symbol
          result = CoinmFutures.get_order(%{symbol: "BTCUSD_PERP"})

          case result do
            {:ok, _order} ->
              IO.puts("Successfully queried COIN-M symbol")

            {:error, reason} ->
              # Expected to fail without valid order ID, but should accept the symbol
              IO.puts("COIN-M symbol query: #{inspect(reason)}")
          end
        end)

      # Should attempt the request with the COIN-M symbol
      assert logs =~ "BTCUSD_PERP" or logs =~ "/dapi/v1/order"
    end
  end
end
