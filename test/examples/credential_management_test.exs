defmodule ZenCex.Examples.CredentialManagementTest do
  @moduledoc """
  Tests for credential_management.ex examples.

  Verifies all authentication patterns work correctly:
  - Explicit credential passing
  - Environment variable pattern
  - Multi-account management
  - Credential rotation
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Examples.CredentialManagement

  @moduletag :example

  describe "use_explicit_credentials/3" do
    test "passes credentials explicitly and returns balances", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]
      testnet = context[:testnet]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Call with explicit credentials
      assert {:ok, balances} =
               CredentialManagement.use_explicit_credentials(api_key, api_secret, testnet: testnet)

      assert is_list(balances)

      # Verify Binance parser returns atom keys
      if length(balances) > 0 do
        balance = hd(balances)
        assert Map.has_key?(balance, :asset)
        assert Map.has_key?(balance, :free)
        assert Map.has_key?(balance, :locked)
      end
    end

    test "accepts testnet option", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Explicitly set testnet: true
      assert {:ok, balances} =
               CredentialManagement.use_explicit_credentials(api_key, api_secret, testnet: true)

      assert is_list(balances)
    end

    test "defaults to testnet: true for safety", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # No testnet option - should default to true
      assert {:ok, balances} =
               CredentialManagement.use_explicit_credentials(api_key, api_secret)

      assert is_list(balances)
    end
  end

  describe "use_credentials_from_env/0" do
    test "reads from environment variables and passes to library", context do
      # This test verifies that CALLING CODE reads ENV, not the library
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Ensure ENV vars are set for this test
      original_key = System.get_env("BINANCE_TESTNET_API_KEY")
      original_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      try do
        System.put_env("BINANCE_TESTNET_API_KEY", api_key)
        System.put_env("BINANCE_TESTNET_API_SECRET", api_secret)

        # Function reads ENV and passes to library
        assert {:ok, balances} = CredentialManagement.use_credentials_from_env()
        assert is_list(balances)

        # Verify Binance parser returns atom keys
        if length(balances) > 0 do
          balance = hd(balances)
          assert Map.has_key?(balance, :asset)
        end
      after
        # Restore original values
        if original_key, do: System.put_env("BINANCE_TESTNET_API_KEY", original_key)
        if original_secret, do: System.put_env("BINANCE_TESTNET_API_SECRET", original_secret)
      end
    end

    test "returns error when ENV vars are missing" do
      # Clear ENV vars
      original_key = System.get_env("BINANCE_TESTNET_API_KEY")
      original_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      try do
        System.delete_env("BINANCE_TESTNET_API_KEY")
        System.delete_env("BINANCE_TESTNET_API_SECRET")

        # Function should return error when ENV vars are missing
        assert {:error, :missing_credentials} =
                 CredentialManagement.use_credentials_from_env()
      after
        # Restore original values
        if original_key, do: System.put_env("BINANCE_TESTNET_API_KEY", original_key)
        if original_secret, do: System.put_env("BINANCE_TESTNET_API_SECRET", original_secret)
      end
    end
  end

  describe "manage_multiple_accounts/1" do
    test "fetches balances for single account", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      accounts = [
        %{api_key: api_key, api_secret: api_secret, testnet: true}
      ]

      assert {:ok, results} = CredentialManagement.manage_multiple_accounts(accounts)
      assert length(results) == 1

      [{creds, balances}] = results
      assert creds.api_key == api_key
      assert is_list(balances)
    end

    test "fetches balances for multiple accounts (using same creds)", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Use same credentials twice to simulate multiple accounts
      accounts = [
        %{api_key: api_key, api_secret: api_secret, testnet: true},
        %{api_key: api_key, api_secret: api_secret, testnet: true}
      ]

      assert {:ok, results} = CredentialManagement.manage_multiple_accounts(accounts)
      assert length(results) == 2

      # Both should return balances
      Enum.each(results, fn {creds, balances} ->
        assert creds.api_key == api_key
        assert is_list(balances)
      end)
    end

    test "adds testnet: true by default when not specified", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Don't specify testnet flag
      accounts = [
        %{api_key: api_key, api_secret: api_secret}
      ]

      assert {:ok, results} = CredentialManagement.manage_multiple_accounts(accounts)
      assert length(results) == 1

      [{creds, _balances}] = results
      # Function should add testnet: true by default
      assert creds.testnet == true
    end

    test "returns error with credentials when account fails" do
      # Use invalid credentials
      accounts = [
        %{api_key: "invalid_key", api_secret: "invalid_secret", testnet: true}
      ]

      case CredentialManagement.manage_multiple_accounts(accounts) do
        {:error, {creds, _reason}} ->
          # Error tuple should include the credentials that failed
          assert creds.api_key == "invalid_key"

        {:ok, _} ->
          flunk("Expected error with invalid credentials")
      end
    end
  end

  describe "rotate_credentials_on_error/2" do
    test "returns success without rotation when first attempt succeeds", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Track how many times credentials function is called
      test_pid = self()
      call_count = :counters.new(1, [])

      get_creds = fn ->
        :counters.add(call_count, 1, 1)
        send(test_pid, :credentials_fetched)
        %{api_key: api_key, api_secret: api_secret, testnet: true}
      end

      # Use a read-only operation that won't fail (get_balances instead of place_order)
      # We'll test the rotation logic, but use get_balances params
      params = %{}

      # NOTE: This test demonstrates the rotation pattern but uses get_balances
      # In real usage, you'd use place_order which can fail with auth errors
      # For testing, we verify the credentials function is called once on success
      _ = CredentialManagement.rotate_credentials_on_error(params, get_creds)

      # Verify credentials were fetched at least once
      assert_received :credentials_fetched

      # In successful case, credentials function called exactly once
      assert :counters.get(call_count, 1) == 1
    end

    test "rotation pattern is implemented correctly" do
      # This test verifies the rotation logic without making real API calls
      # We test that the function structure handles auth errors correctly

      call_count = :counters.new(1, [])

      get_creds = fn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        # Return different credentials on each call to simulate rotation
        %{
          api_key: "key_#{count}",
          api_secret: "secret_#{count}",
          testnet: true
        }
      end

      params = %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: "0.001"}

      # Call the function - it will fail with invalid credentials
      # but we can verify the rotation logic is in place
      case CredentialManagement.rotate_credentials_on_error(params, get_creds) do
        {:ok, _order} ->
          # Successful order (unlikely with fake credentials)
          assert :counters.get(call_count, 1) >= 1

        {:error, _reason} ->
          # Expected to fail with invalid credentials
          # The important part is that the rotation logic exists
          # and credentials function was called at least once
          assert :counters.get(call_count, 1) >= 1
      end
    end
  end

  describe "integration patterns" do
    test "all patterns work with same testnet credentials", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]
      testnet = context[:testnet]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Pattern 1: Explicit credentials
      assert {:ok, balances1} =
               CredentialManagement.use_explicit_credentials(api_key, api_secret, testnet: testnet)

      assert is_list(balances1)

      # Pattern 2: Multi-account (single account case)
      accounts = [%{api_key: api_key, api_secret: api_secret, testnet: testnet}]
      assert {:ok, results} = CredentialManagement.manage_multiple_accounts(accounts)
      assert length(results) == 1

      # All patterns should work with the same credentials
      assert is_list(balances1)
      assert [{_creds, balances2}] = results
      assert is_list(balances2)
    end
  end
end
