defmodule ZenCex.Core.HTTPTest do
  # Need async: false for mocking
  use ExUnit.Case, async: false

  # alias ZenCex.Core.HTTP

  describe "base_request/2" do
    @tag :skip
    test "creates request with default configuration" do
      raise "Not implemented"
    end
  end

  #   # Mock adapter module for testing - simplified without behaviors
  #   defmodule MockAdapter do
  #     def base_url(:prod), do: "https://api.mock.exchange"
  #     def base_url(:test), do: "https://test.api.mock.exchange"
  #     def rate_limiter, do: __MODULE__.RateLimiter
  #     def auth, do: __MODULE__.Auth

  #     defmodule RateLimiter do
  #       def check_and_increment(_endpoint) do
  #         # Check process dictionary for test control
  #         case Process.get(:rate_limit_status, :ok) do
  #           :ok -> :ok
  #           :rate_limited -> {:error, :rate_limited}
  #           {:rate_limited, retry_after} -> {:error, {:rate_limited, retry_after}}
  #         end
  #       end

  #       def update_from_response(_response), do: :ok
  #     end

  #     defmodule Auth do
  #       def sign_request(request, _auth_credentials \\ %{}) do
  #         # Add a test header to verify auth was called
  #         Req.Request.put_header(request, "x-test-auth", "signed")
  #       end
  #     end
  #   end

  #   setup do
  #     # Clear process dictionary
  #     Process.delete(:rate_limit_status)
  #     :ok
  #   end

  #   describe "base_request/2" do
  #     test "creates request with default configuration" do
  #       # Temporarily mock the registry
  #       mock_registry(fn ->
  #         request = HTTP.base_request(:mock)

  #         assert request.options[:finch] == ZenCex.Finch
  #         assert request.options[:base_url] == "https://api.mock.exchange"
  #         assert request.options[:exchange] == :mock
  #         assert request.options[:operation_type] == :standard
  #         assert request.options[:receive_timeout] == 30_000
  #         assert request.options[:max_retries] == 3
  #         assert request.options[:retry] == :safe_transient
  #         assert request.options[:skip_auth] == false
  #         assert request.options[:skip_rate_limit] == false
  #       end)
  #     end

  #     test "sets operation-specific timeouts" do
  #       mock_registry(fn ->
  #         assert HTTP.base_request(:mock, :trading).options[:receive_timeout] == 2_000
  #         assert HTTP.base_request(:mock, :market).options[:receive_timeout] == 5_000
  #         assert HTTP.base_request(:mock, :historical).options[:receive_timeout] == 30_000
  #         assert HTTP.base_request(:mock, :health).options[:receive_timeout] == 5_000
  #         assert HTTP.base_request(:mock, :unknown).options[:receive_timeout] == 30_000
  #       end)
  #     end

  #     test "registers custom options" do
  #       mock_registry(fn ->
  #         request = HTTP.base_request(:mock)

  #         # These options should be registered for use
  #         assert MapSet.member?(request.registered_options, :exchange)
  #         assert MapSet.member?(request.registered_options, :operation_type)
  #         assert MapSet.member?(request.registered_options, :skip_auth)
  #         assert MapSet.member?(request.registered_options, :skip_rate_limit)
  #       end)
  #     end

  #     test "includes auth and rate limit steps" do
  #       mock_registry(fn ->
  #         request = HTTP.base_request(:mock)

  #         # Check that steps are registered
  #         assert {:zen_cex_rate_limit, _} =
  #                  List.keyfind(request.request_steps, :zen_cex_rate_limit, 0)

  #         assert {:zen_cex_auth, _} = List.keyfind(request.request_steps, :zen_cex_auth, 0)

  #         assert {:zen_cex_update_rate_limit, _} =
  #                  List.keyfind(request.response_steps, :zen_cex_update_rate_limit, 0)

  #         assert {:zen_cex_telemetry, _} = List.keyfind(request.error_steps, :zen_cex_telemetry, 0)
  #       end)
  #     end
  #   end

  #   describe "health_check_request/1" do
  #     test "creates request with auth and rate limiting disabled" do
  #       mock_registry(fn ->
  #         request = HTTP.health_check_request(:mock)

  #         assert request.options[:operation_type] == :health
  #         assert request.options[:receive_timeout] == 5_000
  #         assert request.options[:skip_auth] == true
  #         assert request.options[:skip_rate_limit] == true
  #       end)
  #     end
  #   end

  #   describe "rate limiting" do
  #     test "allows request when rate limit is not exceeded" do
  #       mock_registry(fn ->
  #         Process.put(:rate_limit_status, :ok)

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))

  #         # Run the rate limit step directly
  #         {:zen_cex_rate_limit, rate_limit_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_rate_limit, 0)

  #         result = rate_limit_fn.(request)

  #         # Should return the request unchanged
  #         assert %Req.Request{} = result
  #       end)
  #     end

  #     test "returns 429 response when rate limited" do
  #       mock_registry(fn ->
  #         Process.put(:rate_limit_status, :rate_limited)

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))

  #         # Run the rate limit step directly
  #         {:zen_cex_rate_limit, rate_limit_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_rate_limit, 0)

  #         {_request, response} = rate_limit_fn.(request)

  #         assert response.status == 429
  #         assert response.body == "Rate limited"
  #       end)
  #     end

  #     test "returns 429 with retry-after header when retry time is provided" do
  #       mock_registry(fn ->
  #         Process.put(:rate_limit_status, {:rate_limited, 5000})

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))

  #         # Run the rate limit step directly
  #         {:zen_cex_rate_limit, rate_limit_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_rate_limit, 0)

  #         {_request, response} = rate_limit_fn.(request)

  #         assert response.status == 429
  #         assert response.body == "Rate limited"
  #         assert {"retry-after", "5"} in response.headers
  #       end)
  #     end

  #     test "skips rate limiting when skip_rate_limit is true" do
  #       mock_registry(fn ->
  #         Process.put(:rate_limit_status, :rate_limited)

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Req.merge(skip_rate_limit: true)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))

  #         # Run the rate limit step directly
  #         {:zen_cex_rate_limit, rate_limit_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_rate_limit, 0)

  #         result = rate_limit_fn.(request)

  #         # Should return the request unchanged (not rate limited)
  #         assert %Req.Request{} = result
  #       end)
  #     end
  #   end

  #   describe "authentication" do
  #     test "signs request when auth is enabled" do
  #       mock_registry(fn ->
  #         request = HTTP.base_request(:mock)

  #         # Run the auth step directly
  #         {:zen_cex_auth, auth_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_auth, 0)

  #         signed_request = auth_fn.(request)

  #         # Check that our mock auth added the header
  #         assert "signed" in signed_request.headers["x-test-auth"]
  #       end)
  #     end

  #     test "skips auth when skip_auth is true" do
  #       mock_registry(fn ->
  #         request =
  #           HTTP.base_request(:mock)
  #           |> Req.merge(skip_auth: true)

  #         # Run the auth step directly
  #         {:zen_cex_auth, auth_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_auth, 0)

  #         signed_request = auth_fn.(request)

  #         # Should not have the auth header
  #         refute Map.has_key?(signed_request.headers, "x-test-auth")
  #       end)
  #     end
  #   end

  #   describe "exponential backoff" do
  #     test "calculates backoff with jitter" do
  #       mock_registry(fn ->
  #         request = HTTP.base_request(:mock)

  #         # Get the retry delay function
  #         retry_delay_fn = request.options[:retry_delay]

  #         # Test backoff for different retry counts
  #         delay_1 = retry_delay_fn.(1)
  #         # 2^1 * 1000 + jitter
  #         assert delay_1 >= 2000 and delay_1 <= 2500

  #         delay_2 = retry_delay_fn.(2)
  #         # 2^2 * 1000 + jitter
  #         assert delay_2 >= 4000 and delay_2 <= 4500

  #         delay_10 = retry_delay_fn.(10)
  #         # Should cap at 60s + jitter
  #         assert delay_10 <= 60_500

  #         delay_20 = retry_delay_fn.(20)
  #         # Should still cap at 60s + jitter
  #         assert delay_20 <= 60_500
  #       end)
  #     end
  #   end

  #   describe "telemetry" do
  #     test "emits telemetry events on successful response" do
  #       mock_registry(fn ->
  #         # Attach telemetry handler
  #         ref = make_ref()

  #         :telemetry.attach(
  #           "test-handler-#{inspect(ref)}",
  #           [:zen_cex, :request, :complete],
  #           fn event, measurements, metadata, _config ->
  #             send(self(), {:telemetry, event, measurements, metadata})
  #           end,
  #           nil
  #         )

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))
  #           # Manually set start time to simulate real request timing
  #           |> Req.Request.put_private(:zen_cex_start_time, System.monotonic_time() - 1000)

  #         response = %Req.Response{status: 200, body: "OK"}

  #         # Run the telemetry response step
  #         {:zen_cex_telemetry_response, telemetry_fn} =
  #           List.keyfind(request.response_steps, :zen_cex_telemetry_response, 0)

  #         {_request, _response} = telemetry_fn.({request, response})

  #         # Should receive telemetry event
  #         assert_receive {:telemetry, [:zen_cex, :request, :complete], measurements, metadata}

  #         assert measurements[:duration] > 0
  #         assert measurements[:count] == 1
  #         assert metadata[:exchange] == :mock
  #         assert metadata[:operation_type] == :standard
  #         assert metadata[:status] == 200

  #         :telemetry.detach("test-handler-#{inspect(ref)}")
  #       end)
  #     end

  #     test "emits telemetry events on error" do
  #       mock_registry(fn ->
  #         # Attach telemetry handler
  #         ref = make_ref()

  #         :telemetry.attach(
  #           "test-error-handler-#{inspect(ref)}",
  #           [:zen_cex, :request, :error],
  #           fn event, measurements, metadata, _config ->
  #             send(self(), {:telemetry, event, measurements, metadata})
  #           end,
  #           nil
  #         )

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))

  #         exception = %RuntimeError{message: "Connection failed"}

  #         # Run the telemetry error step
  #         {:zen_cex_telemetry, telemetry_fn} =
  #           List.keyfind(request.error_steps, :zen_cex_telemetry, 0)

  #         {_request, _exception} = telemetry_fn.({request, exception})

  #         # Should receive telemetry event
  #         assert_receive {:telemetry, [:zen_cex, :request, :error], measurements, metadata}

  #         assert measurements[:count] == 1
  #         assert metadata[:exchange] == :mock
  #         assert metadata[:operation_type] == :standard
  #         assert metadata[:error] == exception

  #         :telemetry.detach("test-error-handler-#{inspect(ref)}")
  #       end)
  #     end

  #     test "emits rate limit telemetry when rate limited" do
  #       mock_registry(fn ->
  #         # Attach telemetry handler
  #         ref = make_ref()

  #         :telemetry.attach(
  #           "test-rate-limit-handler-#{inspect(ref)}",
  #           [:zen_cex, :rate_limit, :exceeded],
  #           fn event, measurements, metadata, _config ->
  #             send(self(), {:telemetry, event, measurements, metadata})
  #           end,
  #           nil
  #         )

  #         Process.put(:rate_limit_status, {:rate_limited, 5000})

  #         request =
  #           HTTP.base_request(:mock)
  #           |> Map.put(:url, URI.parse("https://api.mock.exchange/test"))

  #         # Run the rate limit step
  #         {:zen_cex_rate_limit, rate_limit_fn} =
  #           List.keyfind(request.request_steps, :zen_cex_rate_limit, 0)

  #         rate_limit_fn.(request)

  #         # Should receive telemetry event
  #         assert_receive {:telemetry, [:zen_cex, :rate_limit, :exceeded], measurements, metadata}

  #         assert measurements[:count] == 1
  #         assert metadata[:exchange] == :mock
  #         assert metadata[:retry_after_ms] == 5000

  #         :telemetry.detach("test-rate-limit-handler-#{inspect(ref)}")
  #       end)
  #     end
  #   end

  #   # Helper to mock the registry for the duration of a test
  #   defp mock_registry(test_fn) do
  #     with_mock ZenCex.Core.Registry,
  #       get_adapter!: fn
  #         :mock -> MockAdapter
  #         exchange -> raise("Unknown exchange: #{exchange}")
  #       end do
  #       test_fn.()
  #     end
  #   end
  # end
end
