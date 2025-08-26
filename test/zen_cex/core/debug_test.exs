defmodule ZenCex.Core.DebugTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.Debug

  setup do
    # Clear any existing debug data
    Debug.clear()

    # Ensure debug is disabled before each test
    Debug.disable()

    # Save original config
    original_config = Application.get_env(:zen_cex, :debug, [])

    on_exit(fn ->
      # Restore original config
      Application.put_env(:zen_cex, :debug, original_config)
      Debug.clear()
      Debug.disable()
    end)

    :ok
  end

  describe "enable/disable" do
    test "enables debug mode at runtime" do
      refute Debug.enabled?()

      Debug.enable()
      assert Debug.enabled?()
    end

    test "disables debug mode at runtime" do
      Debug.enable()
      assert Debug.enabled?()

      Debug.disable()
      refute Debug.enabled?()
    end
  end

  describe "curl_export_enabled?" do
    test "returns false when debug mode is disabled" do
      Debug.disable()
      refute Debug.curl_export_enabled?()
    end

    test "returns true when debug mode is enabled and export_curl is true" do
      Application.put_env(:zen_cex, :debug, enabled: true, export_curl: true)
      assert Debug.curl_export_enabled?()
    end

    test "returns false when debug mode is enabled but export_curl is false" do
      Application.put_env(:zen_cex, :debug, enabled: true, export_curl: false)
      refute Debug.curl_export_enabled?()
    end
  end

  describe "capture_request/2" do
    test "captures nothing when debug mode is disabled" do
      Debug.disable()

      request = build_test_request()
      error = {:error, :test_error}

      assert :ok = Debug.capture_request(request, error)
      assert {:error, :not_found} = Debug.get_last_curl()
    end

    test "captures request when debug mode is enabled" do
      Debug.enable()

      request = build_test_request()
      error = {:error, :test_error}

      assert :ok = Debug.capture_request(request, error)

      # Should have captured the curl command
      assert {:ok, curl} = Debug.get_last_curl()
      assert curl =~ "curl"
      assert curl =~ "https://api.test.com/test"
    end

    test "emits telemetry event when capturing" do
      Debug.enable()

      :telemetry.attach(
        "test-debug-capture",
        [:zen_cex, :debug, :curl_export],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )

      request = build_test_request()
      error = {:error, :test_error}

      Debug.capture_request(request, error)

      assert_receive {:telemetry, %{count: 1}, metadata}
      assert metadata.error == error
      assert metadata.curl_command =~ "curl"

      :telemetry.detach("test-debug-capture")
    end
  end

  describe "export_to_curl/1" do
    test "exports GET request to curl command" do
      request =
        Req.new(
          method: :get,
          url: "https://api.test.com/test",
          headers: [{"x-api-key", "test_key"}]
        )

      assert {:ok, curl} = Debug.export_to_curl(request)
      assert curl =~ "curl"
      assert curl =~ "-X GET"
      assert curl =~ "https://api.test.com/test"
      assert curl =~ "x-api-key: test_key"
    end

    test "exports POST request with body to curl command" do
      request =
        Req.new(
          method: :post,
          url: "https://api.test.com/test",
          headers: [{"content-type", "application/json"}],
          body: Jason.encode!(%{test: "data"})
        )

      assert {:ok, curl} = Debug.export_to_curl(request)
      assert curl =~ "curl"
      assert curl =~ "-X POST"
      # JSON is escaped in curl command
      assert curl =~ "test" && curl =~ "data"
      assert curl =~ "content-type: application/json"
    end

    test "handles request with no body" do
      request =
        Req.new(
          method: :delete,
          url: "https://api.test.com/test/123"
        )

      assert {:ok, curl} = Debug.export_to_curl(request)
      assert curl =~ "curl"
      assert curl =~ "-X DELETE"
      assert curl =~ "https://api.test.com/test/123"
      refute curl =~ " -d "
    end
  end

  describe "get_last_curl/0" do
    test "returns error when no requests captured" do
      Debug.enable()
      assert {:error, :not_found} = Debug.get_last_curl()
    end

    test "returns last captured curl command" do
      Debug.enable()

      # Capture first request
      request1 = build_test_request("https://api.test.com/first")
      Debug.capture_request(request1, {:error, :first})

      # Small delay to ensure different timestamps
      Process.sleep(1)

      # Capture second request
      request2 = build_test_request("https://api.test.com/second")
      Debug.capture_request(request2, {:error, :second})

      assert {:ok, curl} = Debug.get_last_curl()
      assert curl =~ "https://api.test.com/second"
    end
  end

  describe "get_recent_curls/1" do
    test "returns empty list when no requests captured" do
      Debug.enable()
      assert [] = Debug.get_recent_curls(10)
    end

    test "returns limited number of recent curl commands" do
      Debug.enable()

      # Capture multiple requests
      for i <- 1..5 do
        request = build_test_request("https://api.test.com/test#{i}")
        Debug.capture_request(request, {:error, "error#{i}"})
        # Ensure different timestamps
        Process.sleep(1)
      end

      curls = Debug.get_recent_curls(3)
      assert length(curls) == 3

      # Should be in reverse chronological order
      assert Enum.at(curls, 0) =~ "test5"
      assert Enum.at(curls, 1) =~ "test4"
      assert Enum.at(curls, 2) =~ "test3"
    end

    test "handles request for more items than stored" do
      Debug.enable()

      # Capture 2 requests
      for i <- 1..2 do
        request = build_test_request("https://api.test.com/test#{i}")
        Debug.capture_request(request, {:error, "error#{i}"})
        Process.sleep(1)
      end

      curls = Debug.get_recent_curls(10)
      assert length(curls) == 2
    end
  end

  describe "clear/0" do
    test "removes all stored debug data" do
      Debug.enable()

      # Capture some requests
      for i <- 1..3 do
        request = build_test_request("https://api.test.com/test#{i}")
        Debug.capture_request(request, {:error, "error#{i}"})
      end

      # Verify data exists
      assert length(Debug.get_recent_curls(10)) == 3

      # Clear and verify
      assert :ok = Debug.clear()
      assert [] = Debug.get_recent_curls(10)
      assert {:error, :not_found} = Debug.get_last_curl()
    end
  end

  describe "stats/0" do
    test "returns debug statistics" do
      Debug.enable()

      # Capture some requests
      for i <- 1..3 do
        request = build_test_request("https://api.test.com/test#{i}")
        Debug.capture_request(request, {:error, "error#{i}"})
        Process.sleep(1)
      end

      stats = Debug.stats()

      assert stats.total_captured == 3
      assert stats.debug_enabled == true
      assert stats.curl_export_enabled == true
      assert length(stats.recent_errors) == 3
    end

    test "returns empty stats when nothing captured" do
      stats = Debug.stats()

      assert stats.total_captured == 0
      assert stats.recent_errors == []
    end
  end

  describe "cleanup" do
    @max_requests 100

    test "stores all entries when under the limit" do
      Debug.enable()

      # Capture less than max requests
      for i <- 1..50 do
        request = build_test_request("https://api.test.com/test#{i}")
        Debug.capture_request(request, {:error, "error#{i}"})
      end

      # Should keep all entries when under the limit
      stats = Debug.stats()
      assert stats.total_captured == 50
    end

    test "can store exactly the max number of requests" do
      Debug.enable()

      # Capture exactly max requests
      for i <- 1..@max_requests do
        request = build_test_request("https://api.test.com/test#{i}")
        Debug.capture_request(request, {:error, "error#{i}"})
      end

      # Should keep all @max_requests entries
      stats = Debug.stats()
      assert stats.total_captured == @max_requests
    end
  end

  # Helper functions

  defp build_test_request(url \\ "https://api.test.com/test") do
    [method: :get, url: url, headers: [{"x-api-key", "test_key"}]]
    |> Req.new()
    |> Req.Request.put_private(:exchange, :test_exchange)
    |> Req.Request.put_private(:zen_cex_operation, :test_operation)
  end
end
