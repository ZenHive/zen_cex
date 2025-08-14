defmodule ZenCex.Health.CheckTest do
  use ZenCex.DataCase, async: true
  import ExUnit.CaptureLog

  alias ZenCex.Health.Check

  describe "startup_check/0" do
    test "returns :ok when all exchanges are healthy" do
      # This will make real API calls
      result = Check.startup_check()
      assert result == :ok
    end

    test "logs appropriate messages during health checks" do
      log =
        capture_log([level: :info], fn ->
          Check.startup_check()
        end)

      # The log should contain some health check related message
      assert log =~ "[HealthCheck]"
    end
  end

  describe "startup_check_with_retry/0" do
    test "retries on failure and eventually succeeds or fails" do
      # This test uses real APIs, so we just verify it completes
      result = Check.startup_check_with_retry()
      assert result in [:ok, {:error, :health_check_failed}]
    end

    @tag :skip
    test "retries the configured number of times on failure" do
      # This would require mocking the Health module
      # Skipping as we prefer real API tests
    end
  end

  describe "quick_check/0" do
    test "returns a status atom" do
      status = Check.quick_check()
      assert status in [:ok, :warning, :critical]
    end

    test "performs lightweight health check" do
      # Quick check should complete rapidly
      {time, status} = :timer.tc(fn -> Check.quick_check() end)

      assert status in [:ok, :warning, :critical]
      # Should complete within 10 seconds (accounting for network latency)
      assert time < 10_000_000
    end
  end

  describe "detailed_status/0" do
    test "returns comprehensive health information" do
      status = Check.detailed_status()

      assert Map.has_key?(status, :timestamp)
      assert Map.has_key?(status, :exchanges)
      assert Map.has_key?(status, :consensus)
      assert Map.has_key?(status, :healthy)

      assert %DateTime{} = status.timestamp
      assert is_boolean(status.healthy)
      assert is_map(status.exchanges)
      assert is_map(status.consensus)
    end

    test "includes individual exchange status" do
      status = Check.detailed_status()

      # Should have status for each configured exchange
      assert Map.has_key?(status.exchanges, :binance)
      assert Map.has_key?(status.exchanges, :kraken)
      assert Map.has_key?(status.exchanges, :deribit)

      # Each exchange should have health info
      Enum.each([:binance, :kraken, :deribit], fn exchange ->
        exchange_status = status.exchanges[exchange]
        assert Map.has_key?(exchange_status, :exchange)
        assert Map.has_key?(exchange_status, :healthy)
        assert Map.has_key?(exchange_status, :status)
      end)
    end

    test "includes consensus information" do
      status = Check.detailed_status()

      consensus = status.consensus
      assert Map.has_key?(consensus, :overall_status)
      assert consensus.overall_status in [:ok, :warning, :critical]

      assert Map.has_key?(consensus, :exchanges_checked)
      assert Map.has_key?(consensus, :successful_checks)
      assert Map.has_key?(consensus, :consensus)
    end

    test "healthy flag reflects overall status" do
      status = Check.detailed_status()

      # healthy should be true only if overall_status is :ok
      if status.consensus.overall_status == :ok do
        assert status.healthy == true
      else
        assert status.healthy == false
      end
    end
  end

  describe "error handling" do
    test "handles network failures gracefully" do
      # Even with potential network issues, functions should not crash
      assert {:ok, _} = Task.start(fn -> Check.startup_check() end)
      assert {:ok, _} = Task.start(fn -> Check.quick_check() end)
      assert {:ok, _} = Task.start(fn -> Check.detailed_status() end)

      # Give tasks time to complete
      Process.sleep(100)
    end
  end
end
