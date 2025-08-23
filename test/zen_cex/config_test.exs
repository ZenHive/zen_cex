# TODO: Fix this test file - it's messing with environment variables
# The test is modifying System env vars which affects other tests and local development
# Need to properly isolate these tests or use a different approach for testing config
# defmodule ZenCex.ConfigTest do
#   use ExUnit.Case, async: false

#   alias ZenCex.Adapters.Binance.Endpoints
#   alias ZenCex.Config

#   describe "testnet?/1" do
#     test "returns false when environment variable is not set" do
#       System.delete_env("BINANCE_TESTNET")
#       System.delete_env("KRAKEN_TESTNET")
#       System.delete_env("DERIBIT_TESTNET")

#       refute Config.testnet?(:binance)
#       refute Config.testnet?(:kraken)
#       refute Config.testnet?(:deribit)
#     end

#     test "returns true when environment variable is 'true'" do
#       System.put_env("BINANCE_TESTNET", "true")
#       System.put_env("KRAKEN_TESTNET", "true")
#       System.put_env("DERIBIT_TESTNET", "true")

#       assert Config.testnet?(:binance)
#       assert Config.testnet?(:kraken)
#       assert Config.testnet?(:deribit)
#     end

#     test "returns false for other values" do
#       System.put_env("BINANCE_TESTNET", "false")
#       System.put_env("KRAKEN_TESTNET", "1")
#       System.put_env("DERIBIT_TESTNET", "yes")

#       refute Config.testnet?(:binance)
#       refute Config.testnet?(:kraken)
#       refute Config.testnet?(:deribit)
#     end
#   end

#   describe "environment/1" do
#     test "returns :prod when testnet is not enabled" do
#       System.delete_env("BINANCE_TESTNET")
#       assert Config.environment(:binance) == :prod
#     end

#     test "returns :test when testnet is enabled" do
#       System.put_env("BINANCE_TESTNET", "true")
#       assert Config.environment(:binance) == :test
#     end
#   end

#   describe "base_url/1" do
#     test "returns production URLs when testnet is disabled" do
#       System.delete_env("BINANCE_TESTNET")
#       System.delete_env("DERIBIT_TESTNET")

#       assert Config.base_url(:binance) == "https://api.binance.com"
#       assert Config.base_url(:kraken) == "https://api.kraken.com"
#       assert Config.base_url(:deribit) == "https://www.deribit.com"
#     end

#     test "returns testnet URLs when testnet is enabled" do
#       System.put_env("BINANCE_TESTNET", "true")
#       System.put_env("DERIBIT_TESTNET", "true")

#       assert Config.base_url(:binance) == "https://testnet.binance.vision"
#       assert Config.base_url(:deribit) == "https://test.deribit.com"

#       # Kraken uses same URL for both
#       assert Config.base_url(:kraken) == "https://api.kraken.com"
#     end
#   end

#   describe "credentials/1" do
#     setup do
#       # Save original values
#       original_testnet = System.get_env("BINANCE_TESTNET")
#       original_prod_key = System.get_env("BINANCE_API_KEY")
#       original_prod_secret = System.get_env("BINANCE_API_SECRET")
#       original_test_key = System.get_env("BINANCE_TESTNET_API_KEY")
#       original_test_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

#       # Clean up all environment variables
#       System.delete_env("BINANCE_API_KEY")
#       System.delete_env("BINANCE_API_SECRET")
#       System.delete_env("BINANCE_TESTNET_API_KEY")
#       System.delete_env("BINANCE_TESTNET_API_SECRET")
#       System.delete_env("BINANCE_TESTNET")

#       on_exit(fn ->
#         # Restore original values
#         if original_testnet, do: System.put_env("BINANCE_TESTNET", original_testnet)
#         if original_prod_key, do: System.put_env("BINANCE_API_KEY", original_prod_key)
#         if original_prod_secret, do: System.put_env("BINANCE_API_SECRET", original_prod_secret)
#         if original_test_key, do: System.put_env("BINANCE_TESTNET_API_KEY", original_test_key)
#         if original_test_secret, do: System.put_env("BINANCE_TESTNET_API_SECRET", original_test_secret)
#       end)

#       :ok
#     end

#     test "returns production credentials when testnet is disabled" do
#       # NOTE: This test must use production vars to test production mode
#       # but we're in a test environment, so this is safe
#       System.put_env("BINANCE_API_KEY", "prod_key")
#       System.put_env("BINANCE_API_SECRET", "prod_secret")

#       creds = Config.credentials(:binance)
#       assert creds.api_key == "prod_key"
#       assert creds.api_secret == "prod_secret"
#     end

#     test "returns testnet credentials when testnet is enabled" do
#       System.put_env("BINANCE_TESTNET", "true")
#       System.put_env("BINANCE_TESTNET_API_KEY", "test_key")
#       System.put_env("BINANCE_TESTNET_API_SECRET", "test_secret")

#       creds = Config.credentials(:binance)
#       assert creds.api_key == "test_key"
#       assert creds.api_secret == "test_secret"
#     end

#     test "returns nil when credentials are not set" do
#       creds = Config.credentials(:binance)
#       assert creds.api_key == nil
#       assert creds.api_secret == nil
#     end
#   end

#   describe "validate_credentials/1" do
#     setup do
#       # Save original values
#       original_testnet = System.get_env("BINANCE_TESTNET")
#       original_key = System.get_env("BINANCE_API_KEY")
#       original_secret = System.get_env("BINANCE_API_SECRET")
#       original_test_key = System.get_env("BINANCE_TESTNET_API_KEY")
#       original_test_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

#       # Clean up all environment variables for test
#       System.delete_env("BINANCE_TESTNET")
#       System.delete_env("BINANCE_API_KEY")
#       System.delete_env("BINANCE_API_SECRET")
#       System.delete_env("BINANCE_TESTNET_API_KEY")
#       System.delete_env("BINANCE_TESTNET_API_SECRET")

#       on_exit(fn ->
#         # Restore original values
#         if original_testnet, do: System.put_env("BINANCE_TESTNET", original_testnet)
#         if original_key, do: System.put_env("BINANCE_API_KEY", original_key)
#         if original_secret, do: System.put_env("BINANCE_API_SECRET", original_secret)
#         if original_test_key, do: System.put_env("BINANCE_TESTNET_API_KEY", original_test_key)
#         if original_test_secret, do: System.put_env("BINANCE_TESTNET_API_SECRET", original_test_secret)
#       end)

#       :ok
#     end

#     test "returns error when api_key is missing" do
#       # Use testnet vars since we're in test mode
#       System.put_env("BINANCE_TESTNET", "true")
#       System.put_env("BINANCE_TESTNET_API_SECRET", "secret")
#       assert Config.validate_credentials(:binance) == {:error, :missing_api_key}
#     end

#     test "returns error when api_secret is missing" do
#       # Use testnet vars since we're in test mode
#       System.put_env("BINANCE_TESTNET", "true")
#       System.put_env("BINANCE_TESTNET_API_KEY", "key")
#       assert Config.validate_credentials(:binance) == {:error, :missing_api_secret}
#     end

#     test "returns :ok when both credentials are present" do
#       # Use testnet vars since we're in test mode
#       System.put_env("BINANCE_TESTNET", "true")
#       System.put_env("BINANCE_TESTNET_API_KEY", "key")
#       System.put_env("BINANCE_TESTNET_API_SECRET", "secret")
#       assert Config.validate_credentials(:binance) == :ok
#     end
#   end

#   describe "clear_cache/0" do
#     test "clears cached environment values" do
#       # This should not raise even if nothing is cached
#       assert Config.clear_cache() == :ok

#       # Cache something first
#       :persistent_term.put({Endpoints, :current_env}, :test)

#       # Clear it
#       assert Config.clear_cache() == :ok

#       # Verify it's gone
#       assert :persistent_term.get({Endpoints, :current_env}, :not_found) == :not_found
#     end
#   end
# end
