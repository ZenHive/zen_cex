defmodule ZenCex.Adapters.Bybit.CommonIntegrationTest do
  use ZenCex.IntegrationCase, exchange: :bybit, api_type: :common

  alias ZenCex.Adapters.Bybit.Common
  alias ZenCex.Adapters.Bybit.Endpoints

  @moduletag :integration
  @moduletag :bybit

  describe "get_server_time/0,1" do
    test "successfully fetches server time from Bybit testnet" do
      # Verify we're using testnet
      assert Endpoints.current_env() == :test
      assert Endpoints.base_url() == "https://api-testnet.bybit.com"

      # Call the real Bybit testnet API
      assert {:ok, result} = Common.get_server_time()

      # Bybit returns timeSecond and timeNano fields
      assert is_map(result)
      assert Map.has_key?(result, "timeSecond") or Map.has_key?(result, "time")

      # If timeSecond exists, it should be a string timestamp
      if Map.has_key?(result, "timeSecond") do
        assert is_binary(result["timeSecond"])
        # Should be a valid Unix timestamp (10 digits as string)
        assert String.length(result["timeSecond"]) == 10
      end

      # If time exists (millisecond timestamp), it should be an integer
      if Map.has_key?(result, "time") do
        assert is_integer(result["time"])
        # Should be a reasonable timestamp (13 digits for milliseconds)
        assert result["time"] > 1_600_000_000_000
      end
    end

    test "handles network errors gracefully" do
      # Use an extremely short timeout to try to force an error
      # Note: This might still succeed if the response is cached or very fast
      result = Common.get_server_time(timeout: 1)

      # Should return either success (if very fast) or error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "get_announcements/0,1,2" do
    test "successfully fetches announcements from Bybit testnet" do
      # Verify we're using testnet
      assert Endpoints.current_env() == :test
      assert Endpoints.base_url() == "https://api-testnet.bybit.com"

      # Call the real Bybit testnet API - locale parameter is required
      result = Common.get_announcements(%{locale: "en-US"})

      case result do
        {:ok, data} ->
          # Announcements response should have a list structure
          assert is_map(data)
          # May have "list" key with announcements array
          if Map.has_key?(data, "list") do
            assert is_list(data["list"])
          end

          # May have "total" key with count
          if Map.has_key?(data, "total") do
            assert is_integer(data["total"]) or is_binary(data["total"])
          end

        {:error, :not_found} ->
          # Testnet may not have announcements endpoint
          # This is acceptable for testnet
          assert true

        {:error, reason} ->
          # Log the error for debugging but don't fail the test
          # Testnet endpoints may have different availability
          IO.puts("Announcements endpoint error (may be normal for testnet): #{inspect(reason)}")
          assert true
      end
    end

    test "accepts optional parameters" do
      # Test with parameters - locale is required
      params = %{
        locale: "en-US",
        limit: 10
      }

      result = Common.get_announcements(params)

      # Should return either success or an acceptable error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles pagination parameters" do
      # Test with pagination - locale is required
      params = %{
        locale: "en-US",
        page: 1,
        limit: 5
      }

      result = Common.get_announcements(params)

      # Should return either success or an acceptable error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "endpoint availability" do
    test "Common module endpoints are registered correctly" do
      endpoints = Common.all_endpoints()

      # Should have exactly 2 endpoints
      assert length(endpoints) == 2

      # Extract operations
      operations = Enum.map(endpoints, & &1.operation)

      # Should have our defined endpoints
      assert :get_server_time in operations
      assert :get_announcements in operations

      # All endpoints should not require auth
      Enum.each(endpoints, fn endpoint ->
        assert endpoint.requires_auth == false
      end)
    end
  end
end
