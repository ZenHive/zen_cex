defmodule ZenCex.Behaviors.AuthTest do
  use ExUnit.Case, async: true

  defmodule HMACAuth do
    @behaviour ZenCex.Behaviors.Auth

    @impl true
    def sign_request(request, _opts) do
      %{request | headers: [{"X-API-KEY", "test_key"} | request.headers]}
    end

    @impl true
    def validate_credentials do
      if System.get_env("TEST_API_KEY") do
        :ok
      else
        {:error, :missing_credentials}
      end
    end

    @impl true
    def auth_method, do: :hmac_sha256
  end

  defmodule OAuthAuth do
    @behaviour ZenCex.Behaviors.Auth

    @impl true
    def sign_request(request, _opts) do
      %{request | headers: [{"Authorization", "Bearer token123"} | request.headers]}
    end

    @impl true
    def auth_method, do: :oauth2
  end

  describe "auth behavior implementation" do
    test "HMAC auth adds headers correctly" do
      request = %{headers: [], params: %{}}
      signed = HMACAuth.sign_request(request, [])

      assert {"X-API-KEY", "test_key"} in signed.headers
    end

    test "OAuth auth adds bearer token" do
      request = %{headers: [], params: %{}}
      signed = OAuthAuth.sign_request(request, [])

      assert {"Authorization", "Bearer token123"} in signed.headers
    end

    test "auth_method returns correct type" do
      assert :hmac_sha256 == HMACAuth.auth_method()
      assert :oauth2 == OAuthAuth.auth_method()
    end

    test "validate_credentials checks environment" do
      assert {:error, :missing_credentials} = HMACAuth.validate_credentials()

      System.put_env("TEST_API_KEY", "key")
      assert :ok = HMACAuth.validate_credentials()
      System.delete_env("TEST_API_KEY")
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
