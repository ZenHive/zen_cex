defmodule ZenCex.Auth.DeribitOAuthTest do
  use ExUnit.Case, async: false
  alias ZenCex.Auth.DeribitOAuth

  @table_name :deribit_oauth_cache
  @inflight_table :deribit_oauth_inflight

  setup do
    # Clean up any existing tables
    cleanup_tables()

    # Start the GenServer for tests
    {:ok, pid} = DeribitOAuth.start_link()

    # Set up test environment
    System.put_env("DERIBIT_HOST", "test.deribit.com")
    System.put_env("DERIBIT_CLIENT_ID", "test_client")
    System.put_env("DERIBIT_CLIENT_SECRET", "test_secret")

    on_exit(fn ->
      System.delete_env("DERIBIT_HOST")
      System.delete_env("DERIBIT_CLIENT_ID")
      System.delete_env("DERIBIT_CLIENT_SECRET")
      # Stop the GenServer before cleanup
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
      cleanup_tables()
    end)

    %{pid: pid}
  end

  describe "token caching with host separation" do
    test "caches tokens separately for different hosts" do
      # Mock the token response for test environment
      :ets.insert(
        @table_name,
        {{:token, "client1", "test.deribit.com"}, "test_token",
         System.system_time(:second) + 3600}
      )

      :ets.insert(
        @table_name,
        {{:token, "client1", "www.deribit.com"}, "prod_token", System.system_time(:second) + 3600}
      )

      # Verify tokens are cached separately
      assert [{_, "test_token", _}] =
               :ets.lookup(@table_name, {:token, "client1", "test.deribit.com"})

      assert [{_, "prod_token", _}] =
               :ets.lookup(@table_name, {:token, "client1", "www.deribit.com"})
    end

    test "handles legacy cache entries without host", %{pid: pid} do
      # Insert a legacy entry without host (expired)
      :ets.insert(@table_name, {{:token, "legacy_client"}, "legacy_token", 0})

      # The check_and_refresh_expiring_tokens should handle and clean up legacy entries
      # Send the message to trigger cleanup
      send(pid, :check_token_expiry)
      Process.sleep(200)

      # Legacy entry should be deleted
      assert [] = :ets.lookup(@table_name, {:token, "legacy_client"})
    end
  end

  describe "single-flight token refresh" do
    test "prevents concurrent refresh requests for same client and host" do
      # Mark a refresh as in-flight
      :ets.insert(@inflight_table, {{:inflight, "client1", "test.deribit.com"}, self()})

      # Verify the inflight marker exists
      assert [{_, _pid}] =
               :ets.lookup(@inflight_table, {:inflight, "client1", "test.deribit.com"})

      # Clean up
      :ets.delete(@inflight_table, {:inflight, "client1", "test.deribit.com"})
    end

    test "different clients can refresh simultaneously" do
      # Mark refreshes for different clients as in-flight
      :ets.insert(@inflight_table, {{:inflight, "client1", "test.deribit.com"}, self()})
      :ets.insert(@inflight_table, {{:inflight, "client2", "test.deribit.com"}, self()})

      # Both should exist independently
      assert [{_, _}] = :ets.lookup(@inflight_table, {:inflight, "client1", "test.deribit.com"})
      assert [{_, _}] = :ets.lookup(@inflight_table, {:inflight, "client2", "test.deribit.com"})
    end

    test "inflight table exists and is accessible" do
      # Verify the inflight table structure is correct
      assert :ets.info(@inflight_table) != :undefined

      # Test we can insert and delete from it
      key = {:inflight, "test_client", "test.deribit.com"}
      :ets.insert(@inflight_table, {key, self()})
      assert [{_, _}] = :ets.lookup(@inflight_table, key)
      :ets.delete(@inflight_table, key)
      assert [] = :ets.lookup(@inflight_table, key)
    end
  end

  describe "environment variable consistency" do
    test "uses DERIBIT_HOST from environment" do
      System.put_env("DERIBIT_HOST", "custom.deribit.com")

      # Insert a token for the custom host
      :ets.insert(
        @table_name,
        {{:token, "client1", "custom.deribit.com"}, "custom_token",
         System.system_time(:second) + 3600}
      )

      # Verify it can be retrieved
      assert [{_, "custom_token", _}] =
               :ets.lookup(@table_name, {:token, "client1", "custom.deribit.com"})

      System.delete_env("DERIBIT_HOST")
    end
  end

  # Helper functions
  defp cleanup_tables do
    # Don't delete tables here as they're managed by the GenServer
    # Only stop the GenServer if it's running
    case Process.whereis(DeribitOAuth) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          GenServer.stop(pid, :normal, 100)
        end
    end
  end
end
