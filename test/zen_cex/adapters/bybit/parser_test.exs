defmodule ZenCex.Adapters.Bybit.ParserTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.Parser

  describe "parse/1" do
    test "parses successful response with result" do
      response = %{
        status: 200,
        body: ~s({"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT","price":"50000"}})
      }

      assert {:ok, %{"symbol" => "BTCUSDT", "price" => "50000"}} = Parser.parse(response)
    end

    test "parses successful response without result field" do
      response = %{
        status: 200,
        body: ~s({"retCode":0,"retMsg":"OK","serverTime":1672211736359,"data":"value"})
      }

      assert {:ok, %{"serverTime" => 1_672_211_736_359, "data" => "value"}} = Parser.parse(response)
    end

    test "parses rate limit error" do
      response = %{
        status: 429,
        body: ~s({"retCode":10006,"retMsg":"Too many visits!","result":null})
      }

      assert {:error, {:rate_limited, "Too many visits!"}} = Parser.parse(response)
    end

    test "parses authentication error" do
      response = %{
        status: 401,
        body: ~s({"retCode":10004,"retMsg":"error sign!","result":null})
      }

      assert {:error, {:signature_not_valid, "error sign!"}} = Parser.parse(response)
    end

    test "parses insufficient balance error" do
      response = %{
        status: 400,
        body: ~s({"retCode":110004,"retMsg":"Insufficient balance","result":null})
      }

      assert {:error, {:insufficient_balance, "Insufficient balance"}} = Parser.parse(response)
    end

    test "parses order not found error" do
      response = %{
        status: 404,
        body: ~s({"retCode":110001,"retMsg":"Order not found","result":null})
      }

      assert {:error, {:order_not_found, "Order not found"}} = Parser.parse(response)
    end

    test "parses invalid symbol error" do
      response = %{
        status: 400,
        body: ~s({"retCode":110012,"retMsg":"Invalid symbol","result":null})
      }

      assert {:error, {:invalid_symbol, "Invalid symbol"}} = Parser.parse(response)
    end

    test "parses unknown error code with message" do
      response = %{
        status: 400,
        body: ~s({"retCode":99999,"retMsg":"Unknown error occurred","result":null})
      }

      assert {:error, {99_999, "Unknown error occurred"}} = Parser.parse(response)
    end

    test "handles non-integer retCode gracefully" do
      response = %{
        status: 400,
        body: ~s({"retCode":"ERROR","retMsg":"Something went wrong","result":null})
      }

      assert {:error, {"ERROR", "Something went wrong"}} = Parser.parse(response)
    end

    test "handles HTML error response" do
      response = %{
        status: 503,
        body: "<html><head><title>503 Service Unavailable</title></head></html>"
      }

      assert {:error, {:html_error, _}} = Parser.parse(response)
    end

    test "handles CloudFlare protection page" do
      response = %{
        status: 403,
        body: "<html>CloudFlare Ray ID: 123abc</html>"
      }

      assert {:error, {:cdn_error, "CloudFlare protection triggered"}} = Parser.parse(response)
    end

    test "handles invalid JSON response" do
      response = %{
        status: 200,
        body: "not json"
      }

      # With status 200 and invalid JSON, Core.ResponseParser returns http_error
      assert {:error, {:http_error, 200}} = Parser.parse(response)
    end

    test "handles empty response body" do
      response = %{
        status: 200,
        body: ""
      }

      assert {:error, :empty_response} = Parser.parse(response)
    end

    test "handles response without body" do
      response = %{status: 500}
      assert {:error, :internal_server_error} = Parser.parse(response)
    end

    test "handles malformed response structure" do
      response = %{
        status: 200,
        body: ~s({"unexpected":"format","no":"retCode"})
      }

      # Should normalize through Core.ResponseParser
      assert {:ok, %{"unexpected" => "format", "no" => "retCode"}} = Parser.parse(response)
    end
  end

  describe "extract_rate_limits/1" do
    test "extracts rate limits from headers" do
      response = %{
        headers: [
          {"x-ratelimit-remaining", "99"},
          {"x-ratelimit-limit", "100"},
          {"x-ratelimit-reset", "1672211736"}
        ],
        body: ~s({"retCode":0,"retMsg":"OK"})
      }

      limits = Parser.extract_rate_limits(response)
      assert limits.remaining == 99
      assert limits.limit == 100
      assert limits.reset == 1_672_211_736
    end

    test "extracts rate limits from retExtInfo" do
      response = %{
        headers: [],
        body: ~s({
          "retCode":0,
          "retMsg":"OK",
          "result":{},
          "retExtInfo":{
            "rateLimit":100,
            "rateLimitApi":"api/v5/order",
            "rateLimitStatus":"OK"
          }
        })
      }

      limits = Parser.extract_rate_limits(response)
      assert limits.rate_limit == 100
      assert limits.rate_limit_api == "api/v5/order"
      assert limits.rate_limit_status == "OK"
    end

    test "merges rate limits from headers and body" do
      response = %{
        headers: [
          {"x-ratelimit-remaining", "50"}
        ],
        body: ~s({
          "retCode":0,
          "retMsg":"OK",
          "retExtInfo":{"rateLimit":100}
        })
      }

      limits = Parser.extract_rate_limits(response)
      assert limits.remaining == 50
      assert limits.rate_limit == 100
    end

    test "handles missing rate limit info" do
      response = %{
        headers: [],
        body: ~s({"retCode":0,"retMsg":"OK"})
      }

      assert %{} = Parser.extract_rate_limits(response)
    end

    test "handles invalid response structure" do
      assert %{} = Parser.extract_rate_limits(%{})
      assert %{} = Parser.extract_rate_limits(nil)
    end
  end

  describe "error code mappings" do
    test "maps all authentication error codes correctly" do
      test_cases = [
        {10_001, :invalid_request_params},
        {10_002, :invalid_api_key},
        {10_003, :invalid_signature},
        {10_004, :signature_not_valid},
        {10_005, :permission_denied},
        {10_006, :rate_limited},
        {10_007, :api_key_expired},
        {10_008, :invalid_recv_window},
        {10_009, :invalid_timestamp},
        {10_010, :ip_not_whitelisted}
      ]

      for {code, expected_error} <- test_cases do
        response = %{
          status: 401,
          body: Jason.encode!(%{"retCode" => code, "retMsg" => "Error"})
        }

        assert {:error, {^expected_error, "Error"}} = Parser.parse(response)
      end
    end

    test "maps all order error codes correctly" do
      test_cases = [
        {110_001, :order_not_found},
        {110_003, :order_already_canceled},
        {110_004, :insufficient_balance},
        {110_005, :invalid_order_qty},
        {110_007, :invalid_order_price},
        {110_012, :invalid_symbol},
        {110_013, :invalid_order_type},
        {110_014, :invalid_order_side},
        {110_017, :duplicate_order_id},
        {110_025, :position_not_found},
        {110_043, :order_would_trigger_immediately}
      ]

      for {code, expected_error} <- test_cases do
        response = %{
          status: 400,
          body: Jason.encode!(%{"retCode" => code, "retMsg" => "Error"})
        }

        assert {:error, {^expected_error, "Error"}} = Parser.parse(response)
      end
    end

    test "uses message parsing for unknown error codes" do
      response = %{
        status: 400,
        body: ~s({"retCode":99999,"retMsg":"Insufficient balance for order"})
      }

      # Should detect "insufficient" in message
      assert {:error, :insufficient_balance} = Parser.parse(response)
    end
  end
end
