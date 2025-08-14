defmodule ZenCex.HealthTest do
  use ExUnit.Case, async: true

  alias ZenCex.Health

  describe "check_time_sync/2" do
    test "returns :ok when drift is within acceptable range" do
      server_time = System.system_time(:millisecond)
      # 200ms drift (below 300ms warning threshold)
      local_time = server_time + 200

      assert {:ok, %{drift_ms: drift}} = Health.check_time_sync(server_time, local_time)
      assert abs(drift) == 200
    end

    test "returns warning when drift exceeds warning threshold (300ms)" do
      server_time = System.system_time(:millisecond)
      # 400ms drift (above 300ms warning, below 500ms critical)
      local_time = server_time + 400

      assert {:warning, %{drift_ms: drift, threshold_ms: 300}} =
               Health.check_time_sync(server_time, local_time)

      assert abs(drift) == 400
    end

    test "returns critical when drift exceeds critical threshold (500ms)" do
      server_time = System.system_time(:millisecond)
      # 600ms drift (above 500ms critical threshold)
      local_time = server_time + 600

      assert {:critical, %{drift_ms: drift, threshold_ms: 500}} =
               Health.check_time_sync(server_time, local_time)

      assert abs(drift) == 600
    end

    test "handles negative drift correctly" do
      server_time = System.system_time(:millisecond)
      # -400ms drift (warning level)
      local_time = server_time - 400

      assert {:warning, %{drift_ms: drift, threshold_ms: 300}} =
               Health.check_time_sync(server_time, local_time)

      assert drift == -400
    end

    test "uses current system time when local_time not provided" do
      server_time = System.system_time(:millisecond)

      assert {:ok, %{drift_ms: drift}} = Health.check_time_sync(server_time)
      # Drift should be very small since we're comparing to current time
      assert abs(drift) < 100
    end

    test "accepts custom thresholds via options" do
      server_time = System.system_time(:millisecond)
      # 300ms drift
      local_time = server_time + 300

      # With custom warning threshold of 200ms
      assert {:warning, %{drift_ms: 300, threshold_ms: 200}} =
               Health.check_time_sync(server_time, local_time, warning_ms: 200)

      # With custom critical threshold of 250ms
      assert {:critical, %{drift_ms: 300, threshold_ms: 250}} =
               Health.check_time_sync(server_time, local_time, critical_ms: 250)
    end
  end

  describe "parse_server_time/2" do
    test "parses Binance server time from response" do
      response = %{"serverTime" => 1_234_567_890_123}
      assert {:ok, 1_234_567_890_123} = Health.parse_server_time(response, :binance)
    end

    test "parses Kraken server time from response" do
      response = %{
        "error" => [],
        "result" => %{
          "unixtime" => 1_234_567_890,
          "rfc1123" => "Mon, 2 Feb 2009 23:31:30 +0000"
        }
      }

      assert {:ok, 1_234_567_890_000} = Health.parse_server_time(response, :kraken)
    end

    test "parses Deribit server time from response" do
      response = %{
        "jsonrpc" => "2.0",
        "result" => 1_234_567_890_123,
        "usIn" => 1_234_567_890_000,
        "usOut" => 1_234_567_890_123,
        "usDiff" => 123
      }

      assert {:ok, 1_234_567_890_123} = Health.parse_server_time(response, :deribit)
    end

    test "returns error for invalid Binance response" do
      assert {:error, :invalid_server_response} =
               Health.parse_server_time(%{}, :binance)
    end

    test "returns error for invalid Kraken response" do
      assert {:error, :invalid_server_response} =
               Health.parse_server_time(%{"error" => ["EAPI:Invalid key"]}, :kraken)
    end

    test "returns error for invalid Deribit response" do
      assert {:error, :invalid_server_response} =
               Health.parse_server_time(%{"error" => %{"message" => "Invalid"}}, :deribit)
    end

    test "returns error for unknown exchange" do
      assert {:error, :unknown_exchange} =
               Health.parse_server_time(%{}, :unknown)
    end
  end

  describe "format_drift/1" do
    test "formats small drift in milliseconds" do
      assert "50ms" = Health.format_drift(50)
      assert "-50ms" = Health.format_drift(-50)
      assert "999ms" = Health.format_drift(999)
    end

    test "formats medium drift in seconds with decimal" do
      assert "1.5s" = Health.format_drift(1500)
      assert "-2.3s" = Health.format_drift(-2300)
      assert "4.0s" = Health.format_drift(4000)
    end

    test "formats large drift in seconds" do
      assert "10.5s" = Health.format_drift(10500)
      assert "-30.0s" = Health.format_drift(-30000)
    end

    test "handles zero drift" do
      assert "0ms" = Health.format_drift(0)
    end
  end

  describe "get_server_time/1" do
    @tag :integration
    test "fetches server time from Binance" do
      assert {:ok, server_time} = Health.get_server_time(:binance)
      assert is_integer(server_time)
      # After year 2023 in ms
      assert server_time > 1_700_000_000_000
    end

    @tag :integration
    test "fetches server time from Kraken" do
      assert {:ok, server_time} = Health.get_server_time(:kraken)
      assert is_integer(server_time)
      # After year 2023 in ms
      assert server_time > 1_700_000_000_000
    end

    @tag :integration
    test "fetches server time from Deribit" do
      assert {:ok, server_time} = Health.get_server_time(:deribit)
      assert is_integer(server_time)
      # After year 2023 in ms
      assert server_time > 1_700_000_000_000
    end

    test "handles unknown exchange" do
      assert {:error, :unknown_exchange} = Health.get_server_time(:unknown_exchange)
    end
  end

  describe "check_exchange_sync/1" do
    @tag :integration
    test "performs full sync check for Binance" do
      assert {:ok, result} = Health.check_exchange_sync(:binance)
      assert Map.has_key?(result, :exchange)
      assert Map.has_key?(result, :server_time)
      assert Map.has_key?(result, :local_time)
      assert Map.has_key?(result, :drift_ms)
      assert Map.has_key?(result, :status)
      assert result.status in [:ok, :warning, :critical]
    end

    @tag :integration
    test "includes formatted drift in result" do
      assert {:ok, result} = Health.check_exchange_sync(:binance)
      assert Map.has_key?(result, :drift_formatted)
      assert is_binary(result.drift_formatted)
    end

    test "returns error for unknown exchange" do
      assert {:error, :unknown_exchange} = Health.check_exchange_sync(:unknown_exchange)
    end
  end

  describe "periodic_sync_check/2" do
    @tag :integration
    test "performs periodic sync checks" do
      # Start periodic check with 100ms interval
      {:ok, pid} = Health.periodic_sync_check(:binance, 100)

      # Should be a valid pid
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Wait for at least one check
      Process.sleep(150)

      # Stop the periodic checks
      Process.exit(pid, :normal)
    end

    @tag :integration
    test "accepts callback function for results" do
      test_pid = self()

      callback = fn result ->
        send(test_pid, {:sync_result, result})
      end

      {:ok, pid} =
        Health.periodic_sync_check(:binance, 100, callback: callback)

      # Wait for callback to be triggered
      assert_receive {:sync_result, {:ok, result}}, 1000
      assert is_map(result)
      assert Map.has_key?(result, :exchange)
      assert Map.has_key?(result, :drift_ms)

      Process.exit(pid, :normal)
    end
  end
end
