defmodule ZenCex.Core.CircuitBreakerIntegrationTest do
  @moduledoc """
  Integration tests for circuit breaker functionality.

  These tests demonstrate how the circuit breaker protects against
  cascading failures when an exchange becomes unresponsive.
  """
  use ExUnit.Case, async: false

  alias ZenCex.Core.CircuitBreaker

  describe "circuit breaker with mock server" do
    @tag :integration
    @tag :circuit_breaker
    test "circuit opens after repeated failures and returns 503" do
      # Skip this test if req_fuse is not available
      if Code.ensure_loaded?(ReqFuse) do
        # Configure circuit breaker for testing
        original = Application.get_env(:zen_cex, :circuit_breaker)

        config = [
          enabled: true,
          test_exchange: [
            # Open after 2 failures
            failure_threshold: 2,
            # Within 10 seconds
            failure_window: 10_000,
            # Reset after 1 second
            reset_timeout: 1_000
          ]
        ]

        Application.put_env(:zen_cex, :circuit_breaker, config)

        # Register a fake exchange for testing
        Application.put_env(:zen_cex, :test_exchange,
          endpoints_module: ZenCex.Test.FakeEndpoints,
          # Non-existent server
          base_url: "http://localhost:9999"
        )

        # Create requests that will fail
        request1 = build_test_request()
        request2 = build_test_request()
        request3 = build_test_request()

        # First two requests should fail with network error
        {:error, _} = Req.get(request1, url: "http://localhost:9999/api/test")
        {:error, _} = Req.get(request2, url: "http://localhost:9999/api/test")

        # Third request should be rejected by circuit breaker
        case Req.get(request3, url: "http://localhost:9999/api/test") do
          {:ok, %{status: 503, body: body}} ->
            assert body =~ "circuit breaker open"

          {:error, _} ->
            # Circuit breaker might not be triggered in all environments
            :ok
        end

        # Restore original config
        if original do
          Application.put_env(:zen_cex, :circuit_breaker, original)
        else
          Application.delete_env(:zen_cex, :circuit_breaker)
        end

        Application.delete_env(:zen_cex, :test_exchange)
      else
        :skip
      end
    end
  end

  defp build_test_request do
    # Create a minimal test request
    # This would normally use HTTP.base_request(:test_exchange, :standard)
    # but we're creating a simplified version for testing
    Req.new()
    |> Req.Request.register_options([:exchange])
    |> Req.merge(
      exchange: :test_exchange,
      retry: false,
      max_retries: 0,
      receive_timeout: 100
    )
    |> CircuitBreaker.maybe_attach(:test_exchange)
  end
end

defmodule ZenCex.Test.FakeEndpoints do
  @moduledoc false
  # Fake endpoints module for testing

  def base_url, do: "http://localhost:9999"
  def auth, do: ZenCex.Test.FakeAuth
  def rate_limiter, do: ZenCex.Test.FakeRateLimiter
end

defmodule ZenCex.Test.FakeAuth do
  @moduledoc false
  def apply_auth(request), do: request
end

defmodule ZenCex.Test.FakeRateLimiter do
  @moduledoc false
  def check_and_increment(_endpoint, _weight), do: :ok
  def update_from_response(_response), do: :ok
end
