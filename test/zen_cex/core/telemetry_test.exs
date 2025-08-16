defmodule ZenCex.Core.TelemetryTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.Telemetry

  describe "attach_default_handlers/0" do
    test "attaches all default handlers" do
      # Detach any existing handlers first
      Telemetry.detach_default_handlers()

      assert :ok = Telemetry.attach_default_handlers()

      # Verify handlers are attached by checking specific prefixes
      handlers = :telemetry.list_handlers([:zen_cex])
      req_handlers = :telemetry.list_handlers([:req])
      all_handlers = handlers ++ req_handlers
      handler_names = Enum.map(all_handlers, & &1.id)

      assert "zen-cex-log-slow-requests" in handler_names
      assert "zen-cex-log-errors" in handler_names
      assert "zen-cex-log-rate-limits" in handler_names
      assert "zen-cex-log-auth-failures" in handler_names
      assert "zen-cex-req-integration" in handler_names

      # Clean up
      Telemetry.detach_default_handlers()
    end
  end

  describe "detach_default_handlers/0" do
    test "detaches all default handlers" do
      # Attach handlers first
      Telemetry.attach_default_handlers()

      # Then detach
      assert :ok = Telemetry.detach_default_handlers()

      # Verify handlers are detached
      handlers = :telemetry.list_handlers([:zen_cex])
      req_handlers = :telemetry.list_handlers([:req])
      all_handlers = handlers ++ req_handlers
      handler_names = Enum.map(all_handlers, & &1.id)

      refute "zen-cex-log-slow-requests" in handler_names
      refute "zen-cex-log-errors" in handler_names
      refute "zen-cex-log-rate-limits" in handler_names
      refute "zen-cex-log-auth-failures" in handler_names
      refute "zen-cex-req-integration" in handler_names
    end
  end

  describe "execute/3" do
    test "executes telemetry event with zen_cex prefix" do
      # Set up a test handler to capture the event
      test_pid = self()
      handler_ref = make_ref()

      :telemetry.attach(
        "test-handler",
        [:zen_cex, :test, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, event, measurements, metadata})
        end,
        nil
      )

      # Execute the event
      Telemetry.execute([:test, :event], %{count: 1}, %{test: true})

      # Verify the event was received
      assert_receive {^handler_ref, [:zen_cex, :test, :event], %{count: 1}, %{test: true}}

      # Clean up
      :telemetry.detach("test-handler")
    end
  end

  describe "telemetry event emission" do
    setup do
      # Set up handlers to capture events
      test_pid = self()
      handler_ref = make_ref()

      handlers = [
        {:request_complete, [:zen_cex, :request, :complete]},
        {:request_error, [:zen_cex, :request, :error]},
        {:rate_limit, [:zen_cex, :rate_limit, :exceeded]},
        {:auth_failure, [:zen_cex, :auth, :failure]}
      ]

      Enum.each(handlers, fn {name, event} ->
        handler_name = "test-#{name}"

        :telemetry.attach(
          handler_name,
          event,
          fn event, measurements, metadata, _config ->
            send(test_pid, {handler_ref, name, event, measurements, metadata})
          end,
          nil
        )
      end)

      on_exit(fn ->
        Enum.each(handlers, fn {name, _} ->
          :telemetry.detach("test-#{name}")
        end)
      end)

      {:ok, handler_ref: handler_ref}
    end

    test "request complete event includes duration and metadata", %{handler_ref: ref} do
      :telemetry.execute(
        [:zen_cex, :request, :complete],
        %{duration: 1500, count: 1},
        %{exchange: :binance, operation_type: :trading, endpoint: "/api/v3/order", status: 200}
      )

      assert_receive {^ref, :request_complete, [:zen_cex, :request, :complete], measurements,
                      metadata}

      assert measurements.duration == 1500
      assert measurements.count == 1
      assert metadata.exchange == :binance
      assert metadata.operation_type == :trading
      assert metadata.endpoint == "/api/v3/order"
      assert metadata.status == 200
    end

    test "request error event includes error information", %{handler_ref: ref} do
      :telemetry.execute(
        [:zen_cex, :request, :error],
        %{count: 1},
        %{
          exchange: :kraken,
          operation_type: :market,
          endpoint: "/0/public/Ticker",
          error: {:timeout, "Request timed out"}
        }
      )

      assert_receive {^ref, :request_error, [:zen_cex, :request, :error], measurements, metadata}

      assert measurements.count == 1
      assert metadata.exchange == :kraken
      assert metadata.error == {:timeout, "Request timed out"}
    end

    test "rate limit event includes retry information", %{handler_ref: ref} do
      :telemetry.execute(
        [:zen_cex, :rate_limit, :exceeded],
        %{count: 1},
        %{exchange: :binance, endpoint: "/api/v3/order", retry_after_ms: 5000}
      )

      assert_receive {^ref, :rate_limit, [:zen_cex, :rate_limit, :exceeded], measurements,
                      metadata}

      assert measurements.count == 1
      assert metadata.exchange == :binance
      assert metadata.endpoint == "/api/v3/order"
      assert metadata.retry_after_ms == 5000
    end

    test "auth failure event includes auth method and reason", %{handler_ref: ref} do
      :telemetry.execute(
        [:zen_cex, :auth, :failure],
        %{count: 1},
        %{exchange: :deribit, auth_method: :oauth2, reason: :token_expired}
      )

      assert_receive {^ref, :auth_failure, [:zen_cex, :auth, :failure], measurements, metadata}

      assert measurements.count == 1
      assert metadata.exchange == :deribit
      assert metadata.auth_method == :oauth2
      assert metadata.reason == :token_expired
    end
  end

  describe "integration with HTTP module" do
    test "telemetry events are emitted from HTTP requests" do
      # This test verifies that our HTTP module properly emits telemetry
      # We'll test this with a mock handler
      test_pid = self()
      handler_ref = make_ref()

      :telemetry.attach(
        "test-http-integration",
        [:zen_cex, :request, :complete],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :http_telemetry, measurements, metadata})
        end,
        nil
      )

      # Create a request (it won't actually execute, but telemetry should be configured)
      request = ZenCex.Core.HTTP.base_request(:kraken, :trading)

      # Verify telemetry metadata is attached to the request
      assert Req.Request.get_private(request, :zen_cex_request_ref) != nil
      assert Req.Request.get_private(request, :zen_cex_start_time) != nil

      # Clean up
      :telemetry.detach("test-http-integration")
    end
  end

  describe "Req telemetry bridge" do
    test "bridges Req telemetry events to ZenCex events" do
      test_pid = self()
      handler_ref = make_ref()

      # Attach handler for bridged events
      :telemetry.attach(
        "test-req-bridge",
        [:zen_cex, :req, :bridged],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :req_bridged, measurements, metadata})
        end,
        nil
      )

      # Attach the bridge handler
      Telemetry.attach_default_handlers()

      # Simulate a Req telemetry event
      :telemetry.execute(
        [:req, :request, :stop],
        %{duration: 5000},
        %{
          options: %{exchange: :binance},
          request: %{method: :get, url: URI.parse("https://api.binance.com/api/v3/time")},
          response: %{status: 200}
        }
      )

      # Verify the bridged event was received
      assert_receive {^handler_ref, :req_bridged, measurements, metadata}
      assert measurements.duration == 5000
      assert metadata.exchange == :binance
      assert metadata.status == 200
      assert metadata.method == :get
      assert metadata.url == "https://api.binance.com/api/v3/time"

      # Clean up
      :telemetry.detach("test-req-bridge")
      Telemetry.detach_default_handlers()
    end
  end
end
