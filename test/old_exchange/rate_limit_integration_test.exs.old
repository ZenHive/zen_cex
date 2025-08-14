defmodule ZenCex.RateLimitIntegrationTest do
  use ExUnit.Case, async: false
  alias ZenCex.RateLimit

  @moduletag :integration

  describe "integration with real limits" do
    setup do
      # Start the rate limiter
      case Process.whereis(RateLimit) do
        nil ->
          {:ok, _pid} = RateLimit.start_link([])

        _pid ->
          # Already running
          :ok
      end

      :ok
    end

    test "respects Binance spot limits" do
      # Should allow up to 1200 weight per minute
      results =
        for _i <- 1..1210 do
          RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
        end

      success_count = Enum.count(results, &(&1 == :ok))
      failure_count = Enum.count(results, &(&1 == {:error, :rate_limited}))

      assert success_count == 1200
      assert failure_count == 10
    end

    test "respects Binance futures higher limits" do
      # Futures has 2400 weight per minute
      results =
        for _i <- 1..2410 do
          RateLimit.check_and_increment(:binance, "/fapi/v1/order", 1)
        end

      success_count = Enum.count(results, &(&1 == :ok))
      failure_count = Enum.count(results, &(&1 == {:error, :rate_limited}))

      assert success_count == 2400
      assert failure_count == 10
    end

    test "respects Kraken per-second limits" do
      # Should allow 15 per second
      results =
        for _i <- 1..20 do
          RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
        end

      success_count = Enum.count(results, &(&1 == :ok))
      failure_count = Enum.count(results, &(&1 == {:error, :rate_limited}))

      assert success_count == 15
      assert failure_count == 5
    end

    test "respects Deribit per-second limits" do
      # Should allow 20 per second
      results =
        for _i <- 1..25 do
          RateLimit.check_and_increment(:deribit, "/api/v2/private/get_positions", 1)
        end

      success_count = Enum.count(results, &(&1 == :ok))
      failure_count = Enum.count(results, &(&1 == {:error, :rate_limited}))

      assert success_count == 20
      assert failure_count == 5
    end

    test "window reset allows new requests" do
      # Fill Kraken limit
      for _ <- 1..15 do
        assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
      end

      # Should be blocked
      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)

      # Wait for window reset
      Process.sleep(1100)

      # Should work again
      assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
    end

    test "high weight operations count correctly" do
      # One high-weight operation
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 500)

      # Another high-weight operation
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 500)

      # Total is now 1000, can add 200 more
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 200)

      # This would exceed 1200
      assert {:error, :rate_limited} = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
    end

    test "get_usage returns accurate counts" do
      # Add some requests
      for _ <- 1..100 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      {used, limit} = RateLimit.get_usage(:binance_spot)
      assert used == 100
      assert limit == 1200

      # Add to futures
      for _ <- 1..200 do
        RateLimit.check_and_increment(:binance, "/fapi/v1/order", 1)
      end

      {used, limit} = RateLimit.get_usage(:binance_futures)
      assert used == 200
      assert limit == 2400
    end

    test "reset_time provides reasonable values" do
      # Binance uses minute windows
      reset_time = RateLimit.reset_time(:binance_spot)
      assert reset_time > 0 and reset_time <= 60

      # Kraken uses second windows
      reset_time = RateLimit.reset_time(:kraken)
      assert reset_time == 1
    end

    test "update_from_headers processes Binance weight header" do
      # Simulate Binance response header
      headers = [{"x-mbx-used-weight-1m", "750"}]

      assert :ok = RateLimit.update_from_headers(:binance, headers)

      # Usage should reflect the header value
      {used, _limit} = RateLimit.get_usage(:binance_spot)
      assert used >= 750
    end

    test "concurrent access maintains consistency" do
      # Reset by waiting for new window
      Process.sleep(1100)

      # Launch concurrent requests
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            RateLimit.check_and_increment(:binance, "/api/v3/order", 10)
          end)
        end

      results = Task.await_many(tasks)

      # Total weight is 1000, all should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # Check final usage
      {used, _limit} = RateLimit.get_usage(:binance_spot)
      assert used == 1000
    end
  end
end
