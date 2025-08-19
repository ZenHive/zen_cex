defmodule ZenCex.Core.TelemetryHandlerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZenCex.Core.Telemetry

  describe "log_slow_request/4" do
    test "logs warning for requests slower than 1 second" do
      # Test slow request (>1 second)
      log =
        capture_log(fn ->
          Telemetry.log_slow_request(
            [:zen_cex, :request, :complete],
            # 1.5 seconds in microseconds
            %{duration: 1_500_000},
            %{exchange: :binance, endpoint: "/api/v3/order"},
            nil
          )
        end)

      assert log =~ "Slow request to binance /api/v3/order: 1500ms"
      assert log =~ "[warning]"
    end

    test "does not log for fast requests" do
      # Test fast request (<1 second)
      log =
        capture_log(fn ->
          Telemetry.log_slow_request(
            [:zen_cex, :request, :complete],
            # 0.5 seconds in microseconds
            %{duration: 500_000},
            %{exchange: :binance, endpoint: "/api/v3/order"},
            nil
          )
        end)

      assert log == ""
    end

    test "handles edge case of exactly 1 second" do
      log =
        capture_log(fn ->
          Telemetry.log_slow_request(
            [:zen_cex, :request, :complete],
            # Exactly 1 second
            %{duration: 1_000_000},
            %{exchange: :kraken, endpoint: "/0/private/Balance"},
            nil
          )
        end)

      # Should not log as it's not > 1 second
      assert log == ""
    end
  end

  describe "log_error/4" do
    test "logs error with exchange and endpoint details" do
      log =
        capture_log(fn ->
          Telemetry.log_error(
            [:zen_cex, :request, :error],
            %{count: 1},
            %{exchange: :binance, endpoint: "/api/v3/order", error: {:timeout, "Connection timeout"}},
            nil
          )
        end)

      assert log =~ "Request error for binance /api/v3/order"
      assert log =~ "{:timeout, \"Connection timeout\"}"
      assert log =~ "[error]"
    end

    test "logs complex error structures" do
      log =
        capture_log(fn ->
          Telemetry.log_error(
            [:zen_cex, :request, :error],
            %{count: 1},
            %{
              exchange: :kraken,
              endpoint: "/0/private/AddOrder",
              error: %{code: -1121, msg: "Invalid symbol"}
            },
            nil
          )
        end)

      assert log =~ "Request error for kraken /0/private/AddOrder"
      assert log =~ "%{code: -1121, msg: \"Invalid symbol\"}"
    end
  end

  describe "log_rate_limit/4" do
    test "logs rate limit with retry_after_ms" do
      log =
        capture_log(fn ->
          Telemetry.log_rate_limit(
            [:zen_cex, :rate_limit, :exceeded],
            %{count: 1},
            %{exchange: :binance, endpoint: "/api/v3/order", retry_after_ms: 5000},
            nil
          )
        end)

      assert log =~ "Rate limit exceeded for binance /api/v3/order"
      assert log =~ "(retry after 5000ms)"
      assert log =~ "[warning]"
    end

    test "logs rate limit without retry_after_ms" do
      log =
        capture_log(fn ->
          Telemetry.log_rate_limit(
            [:zen_cex, :rate_limit, :exceeded],
            %{count: 1},
            %{exchange: :kraken, endpoint: "/0/public/Ticker"},
            nil
          )
        end)

      assert log =~ "Rate limit exceeded for kraken /0/public/Ticker"
      refute log =~ "retry after"
      assert log =~ "[warning]"
    end

    test "handles nil retry_after_ms explicitly" do
      log =
        capture_log(fn ->
          Telemetry.log_rate_limit(
            [:zen_cex, :rate_limit, :exceeded],
            %{count: 1},
            %{exchange: :deribit, endpoint: "/api/v2/public/get_instruments", retry_after_ms: nil},
            nil
          )
        end)

      assert log =~ "Rate limit exceeded for deribit /api/v2/public/get_instruments"
      refute log =~ "retry after"
    end
  end

  describe "log_auth_failure/4" do
    test "logs auth failure with method and reason" do
      log =
        capture_log(fn ->
          Telemetry.log_auth_failure(
            [:zen_cex, :auth, :failure],
            %{count: 1},
            %{exchange: :deribit, auth_method: :oauth2, reason: "Token expired"},
            nil
          )
        end)

      assert log =~ "Auth failure for deribit using oauth2"
      assert log =~ "Token expired"
      assert log =~ "[error]"
    end

    test "logs auth failure with complex reason" do
      log =
        capture_log(fn ->
          Telemetry.log_auth_failure(
            [:zen_cex, :auth, :failure],
            %{count: 1},
            %{
              exchange: :binance,
              auth_method: :hmac_sha256,
              reason: {:invalid_signature, "Signature verification failed"}
            },
            nil
          )
        end)

      assert log =~ "Auth failure for binance using hmac_sha256"
      assert log =~ "{:invalid_signature, \"Signature verification failed\"}"
    end
  end

  describe "handle_req_stop/4" do
    test "bridges Req events when exchange metadata is present" do
      test_pid = self()
      handler_ref = make_ref()

      # Attach handler to capture bridged event
      :telemetry.attach(
        "test-req-bridge-handler",
        [:zen_cex, :req, :bridged],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :bridged, measurements, metadata})
        end,
        nil
      )

      # Call the handler directly with Req-style metadata
      Telemetry.handle_req_stop(
        [:req, :request, :stop],
        %{duration: 2500},
        %{
          options: %{exchange: :binance},
          request: %{method: :post, url: URI.parse("https://testnet.binance.vision/api/v3/order")},
          response: %{status: 201}
        },
        nil
      )

      # Verify bridged event was emitted
      assert_receive {^handler_ref, :bridged, measurements, metadata}
      assert measurements.duration == 2500
      assert metadata.exchange == :binance
      assert metadata.status == 201
      assert metadata.method == :post
      assert metadata.url == "https://testnet.binance.vision/api/v3/order"

      # Clean up
      :telemetry.detach("test-req-bridge-handler")
    end

    test "does not bridge when exchange metadata is missing" do
      test_pid = self()
      handler_ref = make_ref()

      # Attach handler to capture bridged event
      :telemetry.attach(
        "test-no-bridge-handler",
        [:zen_cex, :req, :bridged],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :should_not_receive, measurements, metadata})
        end,
        nil
      )

      # Call handler without exchange metadata
      result =
        Telemetry.handle_req_stop(
          [:req, :request, :stop],
          %{duration: 1000},
          %{
            # No exchange key
            options: %{},
            request: %{method: :get, url: URI.parse("https://example.com")},
            response: %{status: 200}
          },
          nil
        )

      # Should return nil when not bridging
      assert result == nil

      # Should not receive any event
      refute_receive {^handler_ref, :should_not_receive, _, _}, 100

      # Clean up
      :telemetry.detach("test-no-bridge-handler")
    end

    test "handles missing response gracefully" do
      test_pid = self()
      handler_ref = make_ref()

      :telemetry.attach(
        "test-no-response-handler",
        [:zen_cex, :req, :bridged],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :bridged, measurements, metadata})
        end,
        nil
      )

      # Call handler with nil response
      Telemetry.handle_req_stop(
        [:req, :request, :stop],
        %{duration: 3000},
        %{
          options: %{exchange: :kraken},
          request: %{method: :delete, url: URI.parse("https://api.kraken.com/0/private/CancelOrder")},
          # No response (e.g., network error)
          response: nil
        },
        nil
      )

      # Verify event was emitted with nil status
      assert_receive {^handler_ref, :bridged, measurements, metadata}
      assert measurements.duration == 3000
      assert metadata.exchange == :kraken
      assert metadata.status == nil
      assert metadata.method == :delete

      # Clean up
      :telemetry.detach("test-no-response-handler")
    end

    test "converts various URL types to string" do
      test_pid = self()
      handler_ref = make_ref()

      :telemetry.attach(
        "test-url-conversion",
        [:zen_cex, :req, :bridged],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {handler_ref, :url, metadata.url})
        end,
        nil
      )

      # Test with URI struct
      Telemetry.handle_req_stop(
        [:req, :request, :stop],
        %{duration: 100},
        %{
          options: %{exchange: :test},
          request: %{method: :get, url: URI.parse("https://test.com/api")},
          response: %{status: 200}
        },
        nil
      )

      assert_receive {^handler_ref, :url, url}
      assert url == "https://test.com/api"
      assert is_binary(url)

      # Clean up
      :telemetry.detach("test-url-conversion")
    end
  end

  describe "handler return values" do
    test "all handlers return :ok" do
      # This is important for telemetry handler contract
      assert :ok =
               Telemetry.log_slow_request(
                 nil,
                 %{duration: 2_000_000},
                 %{exchange: :test, endpoint: "/test"},
                 nil
               )

      assert :ok =
               Telemetry.log_error(
                 nil,
                 %{},
                 %{exchange: :test, endpoint: "/test", error: "error"},
                 nil
               )

      assert :ok =
               Telemetry.log_rate_limit(
                 nil,
                 %{},
                 %{exchange: :test, endpoint: "/test", retry_after_ms: 1000},
                 nil
               )

      assert :ok =
               Telemetry.log_auth_failure(
                 nil,
                 %{},
                 %{exchange: :test, auth_method: :test, reason: "reason"},
                 nil
               )
    end
  end

  describe "concurrent handler attachment" do
    test "handles concurrent attach/detach operations safely" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Attach handlers
            Telemetry.attach_default_handlers()
            Process.sleep(:rand.uniform(10))

            # Execute an event
            Telemetry.execute([:test, :concurrent], %{count: i}, %{task: i})

            # Detach handlers
            Telemetry.detach_default_handlers()
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)

      # All operations should complete successfully
      assert Enum.all?(results, &(&1 == :ok))

      # Ensure no handlers are left attached
      Telemetry.detach_default_handlers()
    end
  end
end
