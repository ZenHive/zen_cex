defmodule ZenCex.Adapters.BaseAuthTest do
  use ExUnit.Case, async: false

  import ZenCex.IntegrationCase, only: [with_env: 2]

  alias ZenCex.Adapters.BaseAuth

  # Create a test module that uses BaseAuth
  defmodule TestAuth do
    @moduledoc false
    use BaseAuth, exchange: :test_exchange

    @impl true
    def sign_request(request, api_key, api_secret, opts) do
      # Simple test implementation that adds headers and a signature param
      all_params = opts[:all_params] || %{}

      request
      |> Req.Request.put_header("x-test-api-key", api_key)
      |> Req.Request.put_header("x-test-signature", "test_sig_#{api_secret}")
      |> Req.Request.merge_options(params: Map.put(all_params, "signature", "test_signature"))
    end
  end

  describe "apply_auth/1" do
    test "applies authentication when credentials are available" do
      with_env [
        {"TEST_EXCHANGE_API_KEY", "test_api_key"},
        {"TEST_EXCHANGE_API_SECRET", "test_api_secret"}
      ] do
        request =
          [url: "https://api.test.com/endpoint"]
          |> Req.new()
          |> TestAuth.apply_auth()

        assert Req.Request.get_header(request, "x-test-api-key") == ["test_api_key"]
        assert Req.Request.get_header(request, "x-test-signature") == ["test_sig_test_api_secret"]
        assert request.options[:params]["signature"] == "test_signature"
      end
    end

    test "skips authentication when auth_required is false" do
      with_env [
        {"TEST_EXCHANGE_API_KEY", "test_api_key"},
        {"TEST_EXCHANGE_API_SECRET", "test_api_secret"}
      ] do
        request =
          [url: "https://api.test.com/public"]
          |> Req.new()
          |> Req.Request.put_private(:auth_required, false)
          |> TestAuth.apply_auth()

        assert Req.Request.get_header(request, "x-test-api-key") == []
        assert Req.Request.get_header(request, "x-test-signature") == []
        assert request.options[:params] == nil
      end
    end

    test "passes through request when no credentials available" do
      with_env [
        {"TEST_EXCHANGE_API_KEY", nil},
        {"TEST_EXCHANGE_API_SECRET", nil}
      ] do
        request = Req.new(url: "https://api.test.com/endpoint")
        signed_request = TestAuth.apply_auth(request)

        assert signed_request == request
        assert Req.Request.get_header(signed_request, "x-test-api-key") == []
      end
    end

    test "extracts request parameters correctly" do
      with_env [
        {"TEST_EXCHANGE_API_KEY", "test_api_key"},
        {"TEST_EXCHANGE_API_SECRET", "test_api_secret"}
      ] do
        request =
          [url: "https://api.test.com/endpoint", params: %{"query_param" => "value1"}, json: %{"body_param" => "value2"}]
          |> Req.new()
          |> TestAuth.apply_auth()

        # The sign_request callback should have received merged params
        assert request.options[:params]["signature"] == "test_signature"
      end
    end

    test "handles requests with only query params" do
      with_env [
        {"TEST_EXCHANGE_API_KEY", "test_api_key"},
        {"TEST_EXCHANGE_API_SECRET", "test_api_secret"}
      ] do
        request =
          [url: "https://api.test.com/endpoint", params: %{"symbol" => "BTCUSDT", "limit" => "100"}]
          |> Req.new()
          |> TestAuth.apply_auth()

        assert Req.Request.get_header(request, "x-test-api-key") == ["test_api_key"]
        assert request.options[:params]["signature"] == "test_signature"
      end
    end

    test "handles requests with only body params" do
      with_env [
        {"TEST_EXCHANGE_API_KEY", "test_api_key"},
        {"TEST_EXCHANGE_API_SECRET", "test_api_secret"}
      ] do
        request =
          [url: "https://api.test.com/endpoint", json: %{"symbol" => "BTCUSDT", "quantity" => "1.0"}]
          |> Req.new()
          |> TestAuth.apply_auth()

        assert Req.Request.get_header(request, "x-test-api-key") == ["test_api_key"]
        assert request.options[:params]["signature"] == "test_signature"
      end
    end
  end

  describe "sign_options type" do
    test "sign_request callback receives correct options" do
      # Create a module that captures the options
      defmodule CaptureAuth do
        @moduledoc false
        use BaseAuth, exchange: :test_exchange

        @impl true
        def sign_request(request, _api_key, _api_secret, opts) do
          # Store opts in request private for testing
          Req.Request.put_private(request, :captured_opts, opts)
        end
      end

      with_env [
        {"TEST_EXCHANGE_API_KEY", "key"},
        {"TEST_EXCHANGE_API_SECRET", "secret"}
      ] do
        request =
          [url: "https://api.test.com/endpoint", params: %{"query" => "param"}, json: %{"body" => "param"}]
          |> Req.new()
          |> CaptureAuth.apply_auth()

        captured_opts = request.private[:captured_opts]

        assert is_map(captured_opts[:all_params])
        assert captured_opts[:all_params] == %{"query" => "param", "body" => "param"}
        assert captured_opts[:has_json_option] == true
        assert captured_opts[:body_params] == %{"body" => "param"}
      end
    end
  end
end
