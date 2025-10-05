defmodule ZenCex.Examples.DebugTroubleshootingTest do
  @moduledoc """
  Tests for debug_troubleshooting.ex examples.

  Verifies all debug mode functionality:
  - Enabling/disabling debug mode
  - Capturing failed requests
  - Curl command export
  - Debug statistics
  - Full debug workflow
  """

  use ExUnit.Case

  alias ZenCex.Core.Debug
  alias ZenCex.Examples.DebugTroubleshooting

  @moduletag :example

  setup do
    # Clear any existing debug data before each test
    Debug.clear()
    # Ensure debug is disabled before starting
    Debug.disable()

    on_exit(fn ->
      # Cleanup after each test
      Debug.clear()
      Debug.disable()
    end)

    :ok
  end

  describe "enable_debug_mode/0" do
    test "enables debug mode successfully" do
      assert :ok = DebugTroubleshooting.enable_debug_mode()

      # Verify debug is enabled
      assert Debug.enabled?() == true
    end

    test "can be called multiple times without error" do
      assert :ok = DebugTroubleshooting.enable_debug_mode()
      assert :ok = DebugTroubleshooting.enable_debug_mode()

      assert Debug.enabled?() == true
    end
  end

  describe "disable_debug_mode/0" do
    test "disables debug mode successfully" do
      # First enable
      DebugTroubleshooting.enable_debug_mode()
      assert Debug.enabled?() == true

      # Then disable
      assert :ok = DebugTroubleshooting.disable_debug_mode()
      assert Debug.enabled?() == false
    end

    test "can be called when already disabled" do
      assert :ok = DebugTroubleshooting.disable_debug_mode()
      assert Debug.enabled?() == false
    end

    test "does not clear stored debug data" do
      # Enable and create a failure
      DebugTroubleshooting.enable_debug_mode()
      DebugTroubleshooting.debug_failed_request(%{symbol: "BTCUSDT", side: "BUY"})

      # Disable
      DebugTroubleshooting.disable_debug_mode()

      # Stats should still show captured requests
      stats = DebugTroubleshooting.get_debug_stats()
      assert stats.total_captured > 0
    end
  end

  describe "get_last_curl_command/0" do
    test "returns not_found when no failures captured" do
      assert {:error, :not_found} = DebugTroubleshooting.get_last_curl_command()
    end

    test "returns curl command after failed request" do
      # Enable debug and make failing request
      DebugTroubleshooting.enable_debug_mode()

      assert {:error, _} =
               DebugTroubleshooting.debug_failed_request(%{
                 symbol: "BTCUSDT",
                 side: "BUY"
               })

      # Should now have a curl command
      assert {:ok, curl_command} = DebugTroubleshooting.get_last_curl_command()
      assert is_binary(curl_command)
      assert String.contains?(curl_command, "curl")
    end

    test "curl command contains request details" do
      DebugTroubleshooting.enable_debug_mode()
      DebugTroubleshooting.debug_failed_request(%{symbol: "ETHUSDT", side: "SELL"})

      {:ok, curl_command} = DebugTroubleshooting.get_last_curl_command()

      # Verify curl command structure
      assert String.contains?(curl_command, "curl")
      # Should contain the exchange URL (testnet)
      assert String.contains?(curl_command, "testnet.binance.vision") or
               String.contains?(curl_command, "binance")
    end
  end

  describe "get_debug_stats/0" do
    test "returns stats map with expected keys" do
      stats = DebugTroubleshooting.get_debug_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_captured)
      assert Map.has_key?(stats, :debug_enabled)
      assert Map.has_key?(stats, :curl_export_enabled)
      assert Map.has_key?(stats, :curl_req_available)
      assert Map.has_key?(stats, :recent_errors)
    end

    test "total_captured reflects number of failures" do
      # Initially zero
      stats = DebugTroubleshooting.get_debug_stats()
      assert stats.total_captured == 0

      # Enable and create failures
      DebugTroubleshooting.enable_debug_mode()
      DebugTroubleshooting.debug_failed_request(%{symbol: "BTCUSDT", side: "BUY"})
      DebugTroubleshooting.debug_failed_request(%{symbol: "ETHUSDT", side: "SELL"})

      # Should show 2 captured
      stats = DebugTroubleshooting.get_debug_stats()
      assert stats.total_captured == 2
    end

    test "debug_enabled reflects current state" do
      # Initially disabled
      stats = DebugTroubleshooting.get_debug_stats()
      assert stats.debug_enabled == false

      # Enable
      DebugTroubleshooting.enable_debug_mode()
      stats = DebugTroubleshooting.get_debug_stats()
      assert stats.debug_enabled == true

      # Disable
      DebugTroubleshooting.disable_debug_mode()
      stats = DebugTroubleshooting.get_debug_stats()
      assert stats.debug_enabled == false
    end

    test "recent_errors contains error details" do
      DebugTroubleshooting.enable_debug_mode()
      DebugTroubleshooting.debug_failed_request(%{symbol: "BTCUSDT", side: "BUY"})

      stats = DebugTroubleshooting.get_debug_stats()
      assert is_list(stats.recent_errors)

      if length(stats.recent_errors) > 0 do
        error = hd(stats.recent_errors)
        assert Map.has_key?(error, :error)
        assert Map.has_key?(error, :timestamp)
      end
    end
  end

  describe "debug_failed_request/1" do
    test "returns error when credentials missing" do
      # Save current ENV
      original_key = System.get_env("BINANCE_TESTNET_API_KEY")
      original_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      try do
        # Clear credentials
        System.delete_env("BINANCE_TESTNET_API_KEY")
        System.delete_env("BINANCE_TESTNET_API_SECRET")

        assert {:error, :missing_credentials} =
                 DebugTroubleshooting.debug_failed_request(%{
                   symbol: "BTCUSDT",
                   side: "BUY"
                 })
      after
        # Restore ENV
        if original_key, do: System.put_env("BINANCE_TESTNET_API_KEY", original_key)
        if original_secret, do: System.put_env("BINANCE_TESTNET_API_SECRET", original_secret)
      end
    end

    @tag :integration
    test "creates failing request with testnet credentials" do
      # Need credentials for this test
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      if is_nil(api_key) or is_nil(api_secret) do
        # Skip if no credentials - not a failure
        :ok
      else
        DebugTroubleshooting.enable_debug_mode()

        # This should fail due to invalid parameters
        assert {:error, _reason} =
                 DebugTroubleshooting.debug_failed_request(%{
                   symbol: "BTCUSDT",
                   side: "BUY"
                 })

        # Should be captured
        stats = DebugTroubleshooting.get_debug_stats()
        assert stats.total_captured > 0
      end
    end

    @tag :integration
    test "makes params invalid to guarantee failure" do
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      if is_nil(api_key) or is_nil(api_secret) do
        :ok
      else
        DebugTroubleshooting.enable_debug_mode()

        # Even with reasonable params, should fail due to invalid type
        result =
          DebugTroubleshooting.debug_failed_request(%{
            symbol: "BTCUSDT",
            side: "BUY",
            type: "LIMIT"
            # Function will override type to INVALID_TYPE
          })

        assert {:error, _reason} = result
      end
    end
  end

  describe "full debug workflow" do
    @tag :integration
    test "complete debug troubleshooting workflow" do
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      if is_nil(api_key) or is_nil(api_secret) do
        # Skip integration test if no credentials
        :ok
      else
        # 1. Enable debug mode
        assert :ok = DebugTroubleshooting.enable_debug_mode()
        stats = DebugTroubleshooting.get_debug_stats()
        assert stats.debug_enabled == true

        # 2. Make a failing request
        assert {:error, _} =
                 DebugTroubleshooting.debug_failed_request(%{
                   symbol: "BTCUSDT",
                   side: "BUY"
                 })

        # 3. Get curl command
        assert {:ok, curl_command} = DebugTroubleshooting.get_last_curl_command()
        assert is_binary(curl_command)
        assert String.contains?(curl_command, "curl")

        # 4. Check stats
        stats = DebugTroubleshooting.get_debug_stats()
        assert stats.total_captured >= 1
        assert stats.debug_enabled == true

        # 5. Clear and disable
        Debug.clear()
        assert :ok = DebugTroubleshooting.disable_debug_mode()

        # 6. Verify cleanup
        stats = DebugTroubleshooting.get_debug_stats()
        assert stats.total_captured == 0
        assert stats.debug_enabled == false
      end
    end
  end
end
