defmodule ZenCex.Adapters.Bybit.SignerParameterBuilderIntegrationTest do
  @moduledoc """
  Integration tests to verify Signer and ParameterBuilder work together correctly.
  """
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.ParameterBuilder
  alias ZenCex.Adapters.Bybit.Signer

  describe "Signer and ParameterBuilder integration" do
    test "creates correct signature for GET request with auto-injected category" do
      # Test data from Bybit API documentation examples
      api_key = "testkey"
      api_secret = "testsecret"
      timestamp = "1658385579423"
      recv_window = "5000"

      # Build params with category injection
      params = %{"symbol" => "BTCUSDT", "side" => "BUY"}

      built_params =
        ParameterBuilder.build_params(params, "spot_place_order",
          timestamp: timestamp,
          recv_window: recv_window
        )

      # Verify category was injected
      assert built_params["category"] == "spot"

      # Remove timing params for query string (they go in headers)
      query_params = Map.drop(built_params, ["timestamp", "recv_window"])

      # Create signature
      signature = Signer.create_signature(query_params, api_key, api_secret, timestamp, recv_window)

      # Signature should be a 64-character hex string
      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[a-f0-9]{64}$/)
    end

    test "creates correct signature for POST request with JSON body" do
      api_key = "testkey"
      api_secret = "testsecret"
      timestamp = "1658385579423"
      recv_window = "5000"

      # Build params with category injection
      params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "0.1",
        "price" => "50000"
      }

      built_params =
        ParameterBuilder.build_params(params, "linear_place_order",
          timestamp: timestamp,
          recv_window: recv_window
        )

      # Verify category was injected
      assert built_params["category"] == "linear"

      # Remove timing params for body (they go in headers)
      body_params = Map.drop(built_params, ["timestamp", "recv_window"])

      # Format as JSON for POST
      json_body = ParameterBuilder.format_json_body(body_params)

      # Create signature for POST
      signature = Signer.create_signature(json_body, api_key, api_secret, timestamp, recv_window, method: :post)

      # Signature should be a 64-character hex string
      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[a-f0-9]{64}$/)
    end

    test "signatures are deterministic with same inputs" do
      api_key = "testkey"
      api_secret = "testsecret"
      timestamp = "1658385579423"

      params = %{"symbol" => "BTCUSDT"}
      built_params = ParameterBuilder.build_params(params, "spot_get_balance", timestamp: timestamp)

      query_params = Map.drop(built_params, ["timestamp", "recv_window"])

      # Create signatures multiple times
      sig1 = Signer.create_signature(query_params, api_key, api_secret, timestamp, "5000")
      sig2 = Signer.create_signature(query_params, api_key, api_secret, timestamp, "5000")
      sig3 = Signer.create_signature(query_params, api_key, api_secret, timestamp, "5000")

      # All signatures should be identical
      assert sig1 == sig2
      assert sig2 == sig3
    end

    test "query string is properly formatted and sorted" do
      params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "type" => "LIMIT",
        "quantity" => "1.5",
        "price" => 50_000
      }

      built_params = ParameterBuilder.build_params(params, "spot_place_order", timestamp: "1234567890")

      # Remove timing params
      query_params = Map.drop(built_params, ["timestamp", "recv_window"])

      # Build query string
      query_string = ParameterBuilder.build_query_string(query_params)

      # Should be alphabetically sorted
      expected = "category=spot&price=50000&quantity=1.5&side=BUY&symbol=BTCUSDT&type=LIMIT"
      assert query_string == expected
    end
  end
end
