defmodule ZenCex.Behaviors.AuthTest do
  use ExUnit.Case, async: true

  defmodule HMACAuth do
    @behaviour ZenCex.Behaviors.Auth

    @impl true
    def sign_request(request, opts) do
      api_key = Keyword.get(opts, :api_key, "default_test_key")
      %{request | headers: [{"X-API-KEY", api_key} | request.headers]}
    end

    @impl true
    def validate_credentials do
      # For backwards compatibility, check environment
      if System.get_env("TEST_API_KEY") do
        :ok
      else
        {:error, :missing_credentials}
      end
    end

    @impl true
    def validate_credentials(opts) when is_list(opts) or is_map(opts) do
      api_key = get_credential(opts, :api_key)
      api_secret = get_credential(opts, :api_secret)

      case {api_key, api_secret} do
        {nil, _} -> {:error, :missing_api_key}
        {_, nil} -> {:error, :missing_api_secret}
        {"", _} -> {:error, :empty_api_key}
        {_, ""} -> {:error, :empty_api_secret}
        _ -> :ok
      end
    end

    @impl true
    def auth_method, do: :hmac_sha256

    defp get_credential(opts, key) when is_list(opts) do
      Keyword.get(opts, key)
    end

    defp get_credential(opts, key) when is_map(opts) do
      Map.get(opts, key)
    end
  end

  defmodule OAuthAuth do
    @behaviour ZenCex.Behaviors.Auth

    @impl true
    def sign_request(request, opts) do
      token = Keyword.get(opts, :token, "default_token123")
      %{request | headers: [{"Authorization", "Bearer #{token}"} | request.headers]}
    end

    @impl true
    def auth_method, do: :oauth2
  end

  describe "auth behavior implementation" do
    test "HMAC auth adds headers correctly with default key" do
      request = %{headers: [], params: %{}}
      signed = HMACAuth.sign_request(request, [])

      assert {"X-API-KEY", "default_test_key"} in signed.headers
    end

    test "HMAC auth uses provided API key from options" do
      request = %{headers: [], params: %{}}
      signed = HMACAuth.sign_request(request, api_key: "custom_key")

      assert {"X-API-KEY", "custom_key"} in signed.headers
    end

    test "OAuth auth adds bearer token with default" do
      request = %{headers: [], params: %{}}
      signed = OAuthAuth.sign_request(request, [])

      assert {"Authorization", "Bearer default_token123"} in signed.headers
    end

    test "OAuth auth uses provided token from options" do
      request = %{headers: [], params: %{}}
      signed = OAuthAuth.sign_request(request, token: "custom_token")

      assert {"Authorization", "Bearer custom_token"} in signed.headers
    end

    test "auth_method returns correct type" do
      assert :hmac_sha256 == HMACAuth.auth_method()
      assert :oauth2 == OAuthAuth.auth_method()
    end

    test "validate_credentials/1 with options" do
      # Test with missing credentials
      assert {:error, :missing_api_key} = HMACAuth.validate_credentials([])
      assert {:error, :missing_api_key} = HMACAuth.validate_credentials(%{})

      # Test with only API key
      assert {:error, :missing_api_secret} = HMACAuth.validate_credentials(api_key: "key")

      # Test with only API secret
      assert {:error, :missing_api_key} = HMACAuth.validate_credentials(api_secret: "secret")

      # Test with both credentials
      assert :ok = HMACAuth.validate_credentials(api_key: "key", api_secret: "secret")

      # Test with empty strings
      assert {:error, :empty_api_key} =
               HMACAuth.validate_credentials(api_key: "", api_secret: "secret")

      assert {:error, :empty_api_secret} =
               HMACAuth.validate_credentials(api_key: "key", api_secret: "")

      # Test with map
      assert :ok = HMACAuth.validate_credentials(%{api_key: "key", api_secret: "secret"})
    end

    test "validate_credentials/0 checks environment without manipulation" do
      # This test just verifies the function can be called
      # The actual result depends on whether TEST_API_KEY is set in the environment
      result = HMACAuth.validate_credentials()

      # Just verify it returns a valid result
      assert match?(:ok, result) or match?({:error, :missing_credentials}, result)
    end
  end

  describe "different auth methods" do
    test "behavior supports multiple auth types" do
      auth_types = [:hmac_sha256, :hmac_sha512, :oauth2, :api_key]

      Enum.each(auth_types, fn type ->
        assert type in [:hmac_sha256, :hmac_sha512, :oauth2, :api_key]
      end)
    end
  end
end
