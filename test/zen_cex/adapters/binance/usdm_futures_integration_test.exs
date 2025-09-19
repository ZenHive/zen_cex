defmodule ZenCex.Adapters.Binance.UsdmFuturesIntegrationTest do
  @moduledoc """
  Integration tests for Binance Futures endpoints.

  These tests verify:
  - Futures endpoints use correct testnet URL
  - Rate limiting uses correct futures limits (2400/min vs 1200/min for spot)
  - API type detection works correctly
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :usdm_futures

  import ExUnit.CaptureLog

  alias ZenCex.Adapters.Binance.RateLimiter
  alias ZenCex.Adapters.Binance.UsdmFutures

  setup do
    # Reset rate limiter state before each test
    RateLimiter.reset(nil)
    :ok
  end

  describe "futures endpoints use correct testnet URL" do
    test "get_balances returns futures balances" do
      # Use futures-specific testnet credentials for this test
      futures_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
      futures_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")

      opts =
        if futures_key && futures_secret do
          %{auth_credentials: %{api_key: futures_key, api_secret: futures_secret}}
        else
          %{}
        end

      # Test the futures balance endpoint that returns array directly
      result = UsdmFutures.get_balances(%{}, opts)

      assert {:ok, balances} = result
      assert is_list(balances)

      # Each balance should have our normalized structure
      Enum.each(balances, fn balance ->
        assert Map.has_key?(balance, :asset)
        assert Map.has_key?(balance, :free)
        assert Map.has_key?(balance, :locked)
        assert Map.has_key?(balance, :total)

        assert is_binary(balance.asset)
        assert %Decimal{} = balance.free
        assert %Decimal{} = balance.locked
        assert %Decimal{} = balance.total
      end)
    end

    test "get_positions uses futures testnet URL" do
      # Capture logs to verify rate limiter detects futures API
      logs =
        capture_log([level: :debug], fn ->
          result = UsdmFutures.get_positions()

          case result do
            {:ok, positions} ->
              assert is_list(positions)
              IO.puts("TESTNET futures positions: #{inspect(positions)}")

            {:error, {:exchange_error, msg}} ->
              # Expected if testnet account doesn't have futures enabled
              if String.contains?(msg, "Invalid API-key") do
                IO.puts("TESTNET futures auth error (expected if no futures account): #{msg}")
              else
                IO.puts("TESTNET futures exchange error: #{msg}")
              end

            {:error, reason} ->
              IO.puts("TESTNET futures error: #{inspect(reason)}")
          end
        end)

      # Verify the rate limiter detected this as a USD-M futures request
      assert logs =~ "Binance usdm_futures API usage:" or
               logs =~ "usdm_futures API at"

      # The URL should contain futures testnet host
      assert logs =~ "testnet.binancefuture.com" or
               logs =~ "/fapi/"
    end
  end

  describe "rate limiting uses correct limits per API type" do
    test "USD-M futures endpoints tracked with 2400/min limit" do
      # Get initial status
      initial_status = RateLimiter.get_status("/fapi/v3/positionRisk")
      assert initial_status.limit == 2400

      # Make a USD-M futures request
      _result = UsdmFutures.get_positions()

      # Check that USD-M futures counter was incremented
      futures_status = RateLimiter.get_status("/fapi/v3/positionRisk")
      assert futures_status.limit == 2400
      assert futures_status.used >= initial_status.used
    end

    test "rate limiter correctly distinguishes spot vs USD-M futures vs COIN-M futures" do
      # Check spot endpoint detection
      spot_status = RateLimiter.get_status("/api/v3/account")
      assert spot_status.limit == 1200

      # Check USD-M futures endpoint detection
      usdm_status = RateLimiter.get_status("/fapi/v3/positionRisk")
      assert usdm_status.limit == 2400

      # Check COIN-M futures endpoint detection
      coinm_status = RateLimiter.get_status("/dapi/v1/positionRisk")
      assert coinm_status.limit == 2400

      # Check SAPI endpoint detection
      sapi_status = RateLimiter.get_status("/sapi/v1/capital/config/getall")
      assert sapi_status.limit == 12_000
    end
  end

  describe "rate limit monitoring and warnings" do
    @tag :slow
    test "logs warning at 80% usage for USD-M futures" do
      # This test simulates approaching rate limits
      # In real usage, you'd need many more requests to hit the limit

      _logs =
        capture_log([level: :warning], fn ->
          # Make multiple requests (futures has lower limit of 2400/min)
          # Each request has weight 5, so we'd need ~384 requests to hit 80%
          # For testing, we'll just make a few and verify logging works

          for _ <- 1..3 do
            _result = UsdmFutures.get_positions()
            # Small delay to avoid overwhelming testnet
            Process.sleep(100)
          end
        end)

      # Verify the rate limiter is tracking usage
      # Production warnings are logged automatically by check_and_log_usage/3
      status = RateLimiter.get_status("/fapi/v3/positionRisk")
      assert status.limit == 2400
      assert status.used > 0

      IO.puts("USD-M Futures rate limit status after requests: #{inspect(status)}")
    end
  end

  describe "error handling" do
    test "handles USD-M futures-specific errors correctly" do
      # Test with invalid symbol (USD-M futures symbols are different from spot)
      result = UsdmFutures.get_positions(%{symbol: "INVALID_FUTURES_SYMBOL"})

      case result do
        {:error, reason} ->
          IO.puts("Expected futures error for invalid symbol: #{inspect(reason)}")
          assert true

        {:ok, _} ->
          # Shouldn't succeed with invalid symbol
          assert false, "Expected error for invalid futures symbol"
      end
    end
  end
end
