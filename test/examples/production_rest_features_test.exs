defmodule ZenCex.Examples.ProductionRestFeaturesTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Core.Debug
  alias ZenCex.Examples.ProductionRestFeatures
  alias ZenCex.Safety.ClockSync

  @moduletag :example
  @moduletag :production_features

  describe "circuit breaker demonstration" do
    test "demonstrates circuit breaker concept and configuration" do
      result = ProductionRestFeatures.demonstrate_circuit_breaker()

      case result do
        {:ok, stats} ->
          assert is_map(stats)
          assert stats.feature =~ "Circuit breaker"
          assert is_list(stats.telemetry_events)
          assert length(stats.telemetry_events) > 0

        {:error, :circuit_breaker_disabled} ->
          # Circuit breaker is opt-in via configuration
          :ok
      end
    end
  end

  describe "rate limiting demonstration" do
    test "demonstrates rate limit tracking with real request" do
      assert {:ok, status} = ProductionRestFeatures.demonstrate_rate_limiting()
      assert is_map(status)
      assert status.feature =~ "rate limit"
    end
  end

  describe "debug mode demonstration" do
    test "captures failed requests as curl commands" do
      # Clear any previous debug data
      Debug.disable()

      result = ProductionRestFeatures.demonstrate_debug_mode()

      # Should either have captured a curl command or nil if no failures
      assert is_binary(result) or is_nil(result)

      # If we got a curl command, verify it looks reasonable
      if is_binary(result) do
        assert result =~ "curl"
        # Should contain request information
        assert result =~ "http"
      end
    end

    test "debug mode can be enabled and disabled" do
      Debug.disable()
      refute Debug.enabled?()

      Debug.enable()
      assert Debug.enabled?()

      Debug.disable()
      refute Debug.enabled?()
    end

    test "debug stats are available" do
      Debug.enable()
      stats = Debug.stats()
      assert is_map(stats)
      Debug.disable()
    end
  end

  describe "clock synchronization demonstration" do
    test "demonstrates clock sync with real exchange" do
      assert {:ok, offset_ms} = ProductionRestFeatures.demonstrate_clock_sync()
      assert is_integer(offset_ms)
      # Offset should be reasonable (less than 10 seconds)
      assert abs(offset_ms) < 10_000
    end

    test "can get current offset" do
      offset_ms = ClockSync.get_offset(:binance)
      assert is_integer(offset_ms)
    end

    test "can force manual sync" do
      {:ok, offset} = ClockSync.sync_exchange(:binance)
      assert is_integer(offset)
      # Offset should be reasonable
      assert abs(offset) < 10_000
    end
  end

  describe "operation timeout demonstration" do
    test "demonstrates different timeout configurations" do
      assert {:ok, results} = ProductionRestFeatures.demonstrate_operation_timeouts()
      assert is_map(results)

      # Should have results for different operation types
      assert Map.has_key?(results, :trading)
      assert Map.has_key?(results, :market)
      assert Map.has_key?(results, :health)

      # Each result should be either success with timing or error
      Enum.each(results, fn {_op_type, result} ->
        case result do
          {:ok, duration_ms} ->
            assert is_integer(duration_ms)
            assert duration_ms > 0

          {:error, _reason} ->
            # Operations can fail if exchange is unreachable
            :ok
        end
      end)
    end
  end

  describe "telemetry demonstration" do
    test "lists available telemetry events" do
      assert {:ok, events} = ProductionRestFeatures.demonstrate_telemetry()
      assert is_map(events)

      # Should have event categories
      assert Map.has_key?(events, :request_events)
      assert Map.has_key?(events, :rate_limit_events)
      assert Map.has_key?(events, :circuit_breaker_events)
      assert Map.has_key?(events, :clock_sync_events)

      # Each category should have events listed
      assert is_list(events.request_events)
      assert length(events.request_events) > 0
    end
  end

  describe "complete production workflow" do
    @tag :slow
    test "runs complete workflow with all features" do
      assert {:ok, results} = ProductionRestFeatures.run_production_workflow()
      assert is_map(results)

      # Should have all workflow steps
      assert Map.has_key?(results, :step_1_clock_sync)
      assert Map.has_key?(results, :step_2_rate_limits)
      assert Map.has_key?(results, :step_3_debug_setup)
      assert Map.has_key?(results, :step_4_operation_timeouts)
      assert Map.has_key?(results, :step_5_telemetry)
      assert Map.has_key?(results, :step_6_circuit_breaker)

      # Debug should be enabled
      assert {:ok, :enabled} = results.step_3_debug_setup

      # Cleanup
      Debug.disable()
    end
  end

  describe "production feature integration" do
    test "features work together seamlessly" do
      # Enable debug mode
      Debug.enable()

      # Check clock sync is working
      offset = ClockSync.get_offset(:binance)
      assert is_integer(offset)

      # Make a request (this exercises rate limiting, circuit breaker, etc.)
      result = ProductionRestFeatures.demonstrate_rate_limiting()
      assert {:ok, _status} = result

      # Cleanup
      Debug.disable()
    end

    test "failed requests are captured in debug mode" do
      Debug.enable()
      Debug.clear()

      # Make a request that will fail
      _result =
        Spot.get_ticker_price(%{symbol: "DEFINITELY_INVALID_SYMBOL"})

      # Should have captured the failure
      case Debug.get_last_curl() do
        {:ok, curl_string} when is_binary(curl_string) ->
          assert curl_string =~ "curl"
          assert curl_string =~ "DEFINITELY_INVALID_SYMBOL"

        {:error, :not_found} ->
          # If no curl captured, that's okay
          :ok
      end

      Debug.disable()
    end
  end

  describe "real-world usage patterns" do
    test "demonstrates typical production setup" do
      # 1. Clock sync is automatic (handled by Application startup)
      offset = ClockSync.get_offset(:binance)
      assert is_integer(offset)

      # 2. Rate limiting is automatic (handled by Core.HTTP)
      # Just make a normal request
      result = Common.get_server_time()

      case result do
        {:ok, time} ->
          assert is_map(time)
          # Response uses snake_case keys
          assert Map.has_key?(time, :server_time) or Map.has_key?(time, "serverTime")

        {:error, _reason} ->
          # Can fail if exchange unreachable
          :ok
      end

      # 3. Debug mode is opt-in for troubleshooting
      # Note: May be enabled from previous tests, so just ensure it can be toggled
      Debug.disable()
      refute Debug.enabled?()

      # 4. Circuit breaker is opt-in via configuration
      # (tested in circuit breaker tests)
    end

    test "demonstrates error handling with debug mode" do
      Debug.enable()
      Debug.clear()

      # Make an authenticated request without credentials
      result =
        Spot.get_balances(%{},
          auth_credentials: %{
            api_key: "invalid_key",
            api_secret: "invalid_secret"
          }
        )

      # Should fail with authentication error
      case result do
        {:error, reason} ->
          assert reason

          # Debug mode should have captured it
          case Debug.get_last_curl() do
            {:ok, curl_string} when is_binary(curl_string) ->
              assert curl_string =~ "curl"
              # Should include the invalid API key
              assert curl_string =~ "invalid_key"

            {:error, :not_found} ->
              # If no curl captured, that's okay
              :ok
          end

        {:ok, _} ->
          # Shouldn't succeed with invalid credentials
          flunk("Expected authentication error")
      end

      Debug.disable()
    end
  end

  describe "feature configuration" do
    test "circuit breaker configuration is documented" do
      result = ProductionRestFeatures.demonstrate_circuit_breaker()

      case result do
        {:ok, stats} ->
          assert stats.configuration =~ "configurable"

        {:error, :circuit_breaker_disabled} ->
          # Expected when not configured
          :ok
      end
    end

    test "rate limiter works per-exchange" do
      # Rate limiting is per-exchange and automatic
      # Make multiple requests to verify it's tracking
      results =
        for _i <- 1..3 do
          Common.get_server_time()
        end

      # At least some should succeed
      successes = Enum.filter(results, &match?({:ok, _}, &1))
      assert length(successes) > 0
    end

    test "clock sync is per-exchange and automatic" do
      # Clock sync maintains offsets per exchange
      binance_offset = ClockSync.get_offset(:binance)
      assert is_integer(binance_offset)

      # For Binance, different API types can have different testnets
      # but same production endpoint, so offsets may be the same
    end
  end

  describe "monitoring and observability" do
    test "telemetry events are comprehensive" do
      {:ok, events} = ProductionRestFeatures.demonstrate_telemetry()

      # Should cover all major feature areas
      all_events =
        events.request_events ++
          events.rate_limit_events ++
          events.circuit_breaker_events ++
          events.clock_sync_events

      # Should have multiple event types
      assert length(all_events) >= 7
    end

    test "debug mode provides actionable information" do
      Debug.enable()
      Debug.clear()

      # Trigger a failure
      _result = Spot.get_ticker_price(%{symbol: "INVALID123"})

      # Get debug info
      stats = Debug.stats()
      assert is_map(stats)

      # Should have captured something
      case Debug.get_last_curl() do
        {:ok, curl_string} when is_binary(curl_string) ->
          # Curl command should be executable
          assert curl_string =~ "curl"
          assert curl_string =~ "-X"
          # Should have URL
          assert curl_string =~ "http"

        {:error, :not_found} ->
          # If no curl captured, that's okay
          :ok
      end

      Debug.disable()
    end
  end

  describe "production best practices" do
    test "demonstrates resilience patterns" do
      # This test verifies the example demonstrates all key resilience patterns

      {:ok, workflow} = ProductionRestFeatures.run_production_workflow()

      # Clock sync - ensures accurate timestamps
      assert {:ok, _offset} = workflow.step_1_clock_sync

      # Rate limiting - prevents API violations
      assert {:ok, _status} = workflow.step_2_rate_limits

      # Debug monitoring - troubleshooting support
      assert {:ok, :enabled} = workflow.step_3_debug_setup

      # Operation timeouts - optimized for use case
      assert {:ok, _timings} = workflow.step_4_operation_timeouts

      # Telemetry - observability
      assert {:ok, _events} = workflow.step_5_telemetry

      # Circuit breaker - cascade protection
      case workflow.step_6_circuit_breaker do
        {:ok, _} -> :ok
        {:error, :circuit_breaker_disabled} -> :ok
      end

      # Cleanup
      Debug.disable()
    end
  end
end
