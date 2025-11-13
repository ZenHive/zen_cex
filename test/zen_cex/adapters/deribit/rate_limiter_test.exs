defmodule ZenCex.Adapters.Deribit.RateLimiterTest do
  # async: false required - tests share :deribit_limiter ETS table
  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Deribit.RateLimiter

  # Clean up ETS table after each test
  setup do
    on_exit(fn ->
      if :ets.whereis(:deribit_limiter) != :undefined do
        :ets.delete(:deribit_limiter)
      end
    end)

    :ok
  end

  describe "init/0" do
    test "initializes rate limiter with 100-credit bucket" do
      assert {:ok, :deribit_limiter} = RateLimiter.init()
      assert {:ok, %{tokens: 100, queue_size: 0}} = RateLimiter.get_status()
    end
  end

  describe "check_rate_limit/1 - credit costs" do
    setup do
      {:ok, :deribit_limiter} = RateLimiter.init()
      :ok
    end

    test "public methods cost 1 credit" do
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "public/get_ticker"})
      assert {:ok, %{tokens: 99, queue_size: 0}} = RateLimiter.get_status()

      assert :ok = RateLimiter.check_rate_limit(%{"method" => "public/get_order_book"})
      assert {:ok, %{tokens: 98, queue_size: 0}} = RateLimiter.get_status()
    end

    test "private get_* methods cost 5 credits" do
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/get_positions"})
      assert {:ok, %{tokens: 95, queue_size: 0}} = RateLimiter.get_status()

      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/get_open_orders"})
      assert {:ok, %{tokens: 90, queue_size: 0}} = RateLimiter.get_status()
    end

    test "private set_* methods cost 10 credits" do
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/set_email_language"})
      assert {:ok, %{tokens: 90, queue_size: 0}} = RateLimiter.get_status()

      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/set_announcement_as_read"})
      assert {:ok, %{tokens: 80, queue_size: 0}} = RateLimiter.get_status()
    end

    test "trading methods cost 15 credits" do
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 85, queue_size: 0}} = RateLimiter.get_status()

      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/sell"})
      assert {:ok, %{tokens: 70, queue_size: 0}} = RateLimiter.get_status()
    end

    test "other private methods default to 5 credits" do
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/cancel"})
      assert {:ok, %{tokens: 95, queue_size: 0}} = RateLimiter.get_status()
    end
  end

  describe "check_rate_limit/1 - rate limiting behavior" do
    setup do
      {:ok, :deribit_limiter} = RateLimiter.init()
      :ok
    end

    test "returns :ok when credits available" do
      # Consume 85 credits (15 for buy)
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 85, queue_size: 0}} = RateLimiter.get_status()

      # Still have credits for another buy
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 70, queue_size: 0}} = RateLimiter.get_status()
    end

    test "returns {:error, :rate_limited} when credits exhausted" do
      # Consume 90 credits (6 x 15)
      for _ <- 1..6 do
        assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      end

      assert {:ok, %{tokens: 10, queue_size: 0}} = RateLimiter.get_status()

      # Next request requires 15 credits but only 10 available
      assert {:error, :rate_limited} = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 10, queue_size: 1}} = RateLimiter.get_status()
    end

    test "queues multiple requests when rate limited" do
      # Exhaust credits (6 x 15 = 90, leaving 10)
      for _ <- 1..6 do
        assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      end

      assert {:ok, %{tokens: 10, queue_size: 0}} = RateLimiter.get_status()

      # Queue buy request (needs 15, only 10 available)
      assert {:error, :rate_limited} =
               RateLimiter.check_rate_limit(%{"method" => "private/buy"})

      assert {:ok, %{tokens: 10, queue_size: 1}} = RateLimiter.get_status()

      # Queue another buy request
      assert {:error, :rate_limited} =
               RateLimiter.check_rate_limit(%{"method" => "private/buy"})

      assert {:ok, %{tokens: 10, queue_size: 2}} = RateLimiter.get_status()
    end

    test "returns {:error, :queue_full} when queue exceeds 100 requests" do
      # Exhaust credits
      for _ <- 1..100 do
        assert :ok = RateLimiter.check_rate_limit(%{"method" => "public/ticker"})
      end

      # Queue 100 requests
      for _ <- 1..100 do
        assert {:error, :rate_limited} =
                 RateLimiter.check_rate_limit(%{"method" => "public/ticker"})
      end

      assert {:ok, %{tokens: 0, queue_size: 100}} = RateLimiter.get_status()

      # 101st request should fail with queue_full
      assert {:error, :queue_full} =
               RateLimiter.check_rate_limit(%{"method" => "public/ticker"})
    end
  end

  describe "get_status/0" do
    setup do
      {:ok, :deribit_limiter} = RateLimiter.init()
      :ok
    end

    test "returns current tokens and queue size" do
      assert {:ok, %{tokens: 100, queue_size: 0}} = RateLimiter.get_status()
    end

    test "reflects tokens consumed" do
      RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 85, queue_size: 0}} = RateLimiter.get_status()

      RateLimiter.check_rate_limit(%{"method" => "public/ticker"})
      assert {:ok, %{tokens: 84, queue_size: 0}} = RateLimiter.get_status()
    end

    test "reflects queue growth when rate limited" do
      # Exhaust credits
      for _ <- 1..20 do
        RateLimiter.check_rate_limit(%{"method" => "private/get_positions"})
      end

      # Queue requests
      RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 0, queue_size: 1}} = RateLimiter.get_status()

      RateLimiter.check_rate_limit(%{"method" => "private/sell"})
      assert {:ok, %{tokens: 0, queue_size: 2}} = RateLimiter.get_status()
    end
  end

  describe "reset/0" do
    test "resets limiter to initial state" do
      {:ok, :deribit_limiter} = RateLimiter.init()

      # Consume credits
      RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      RateLimiter.check_rate_limit(%{"method" => "private/sell"})
      assert {:ok, %{tokens: 70, queue_size: 0}} = RateLimiter.get_status()

      # Reset
      assert :ok = RateLimiter.reset()

      # Should be back to initial state
      assert {:ok, %{tokens: 100, queue_size: 0}} = RateLimiter.get_status()
    end

    test "clears queue when reset" do
      {:ok, :deribit_limiter} = RateLimiter.init()

      # Exhaust credits and queue requests
      for _ <- 1..6 do
        RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      end

      RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 10, queue_size: 1}} = RateLimiter.get_status()

      # Reset
      assert :ok = RateLimiter.reset()

      # Queue should be cleared
      assert {:ok, %{tokens: 100, queue_size: 0}} = RateLimiter.get_status()
    end

    test "works when limiter not initialized" do
      # Should not crash if limiter doesn't exist
      assert :ok = RateLimiter.reset()
      assert {:ok, %{tokens: 100, queue_size: 0}} = RateLimiter.get_status()
    end
  end

  describe "mixed request pattern" do
    setup do
      {:ok, :deribit_limiter} = RateLimiter.init()
      :ok
    end

    test "handles realistic trading session" do
      # Public ticker (1 credit)
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "public/get_ticker"})
      assert {:ok, %{tokens: 99}} = RateLimiter.get_status()

      # Get positions (5 credits)
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/get_positions"})
      assert {:ok, %{tokens: 94}} = RateLimiter.get_status()

      # Place buy order (15 credits)
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      assert {:ok, %{tokens: 79}} = RateLimiter.get_status()

      # Get open orders (5 credits)
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/get_open_orders"})
      assert {:ok, %{tokens: 74}} = RateLimiter.get_status()

      # Cancel order (5 credits)
      assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/cancel"})
      assert {:ok, %{tokens: 69}} = RateLimiter.get_status()
    end

    test "handles burst trading" do
      # Rapid fire 6 trades (6 x 15 = 90 credits)
      for _ <- 1..6 do
        assert :ok = RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      end

      assert {:ok, %{tokens: 10, queue_size: 0}} = RateLimiter.get_status()

      # 7th trade should be rate limited
      assert {:error, :rate_limited} =
               RateLimiter.check_rate_limit(%{"method" => "private/sell"})

      assert {:ok, %{tokens: 10, queue_size: 1}} = RateLimiter.get_status()
    end
  end
end
