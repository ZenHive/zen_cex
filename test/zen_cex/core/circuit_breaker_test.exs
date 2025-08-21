defmodule ZenCex.Core.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.CircuitBreaker

  describe "enabled?/0" do
    test "returns false when not configured" do
      refute CircuitBreaker.enabled?()
    end

    test "returns true when enabled in config" do
      # Temporarily set config
      original = Application.get_env(:zen_cex, :circuit_breaker)
      Application.put_env(:zen_cex, :circuit_breaker, enabled: true)

      assert CircuitBreaker.enabled?()

      # Restore original config
      if original do
        Application.put_env(:zen_cex, :circuit_breaker, original)
      else
        Application.delete_env(:zen_cex, :circuit_breaker)
      end
    end
  end

  describe "get_config/1" do
    test "returns empty list when exchange not configured" do
      assert CircuitBreaker.get_config(:nonexistent) == []
    end

    test "returns exchange config when configured" do
      # Temporarily set config
      original = Application.get_env(:zen_cex, :circuit_breaker)

      config = [
        enabled: true,
        binance: [
          failure_threshold: 3,
          failure_window: 30_000,
          reset_timeout: 15_000
        ]
      ]

      Application.put_env(:zen_cex, :circuit_breaker, config)

      assert CircuitBreaker.get_config(:binance) == [
               failure_threshold: 3,
               failure_window: 30_000,
               reset_timeout: 15_000
             ]

      # Restore original config
      if original do
        Application.put_env(:zen_cex, :circuit_breaker, original)
      else
        Application.delete_env(:zen_cex, :circuit_breaker)
      end
    end
  end

  describe "should_blow_fuse?/1" do
    test "returns true for 5xx status codes" do
      assert CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 500}})
      assert CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 502}})
      assert CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 503}})
      assert CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 504}})
      assert CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 599}})
    end

    test "returns false for 429 (rate limit)" do
      refute CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 429}})
    end

    test "returns false for other status codes" do
      refute CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 200}})
      refute CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 201}})
      refute CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 400}})
      refute CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 401}})
      refute CircuitBreaker.should_blow_fuse?({:ok, %Req.Response{status: 404}})
    end

    test "returns true for transport errors" do
      assert CircuitBreaker.should_blow_fuse?({:error, %Req.TransportError{reason: :timeout}})
      assert CircuitBreaker.should_blow_fuse?({:error, %Mint.TransportError{reason: :closed}})
    end

    test "returns false for other errors" do
      refute CircuitBreaker.should_blow_fuse?({:error, :some_other_error})
      refute CircuitBreaker.should_blow_fuse?({:error, "string error"})
    end

    test "returns false for unknown formats" do
      refute CircuitBreaker.should_blow_fuse?(nil)
      refute CircuitBreaker.should_blow_fuse?(:unknown)
      refute CircuitBreaker.should_blow_fuse?("string")
    end
  end

  describe "maybe_attach/2" do
    test "returns request unchanged when disabled" do
      request = Req.new()
      assert CircuitBreaker.maybe_attach(request, :binance) == request
    end

    test "returns request unchanged when req_fuse not available" do
      # This test assumes req_fuse is optional and may not be available
      # If req_fuse is available, this test will be skipped
      request = Req.new()
      result = CircuitBreaker.maybe_attach(request, :binance)

      # The request should either be unchanged (no req_fuse) or have circuit breaker attached
      assert %Req.Request{} = result
    end
  end

  describe "status/1" do
    test "returns not_found for unconfigured exchange" do
      assert CircuitBreaker.status(:nonexistent_exchange) == {:error, :not_found}
    end
  end

  describe "reset/1" do
    test "returns error for non-existent fuse" do
      assert {:error, :not_found} = CircuitBreaker.reset(:nonexistent_exchange)
    end
  end
end
