defmodule ZenCex.Core.ResponseParserTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.ResponseParser

  describe "map_http_status_to_error/1" do
    test "maps common HTTP status codes to error atoms" do
      assert ResponseParser.map_http_status_to_error(400) == :bad_request
      assert ResponseParser.map_http_status_to_error(401) == :unauthorized
      assert ResponseParser.map_http_status_to_error(403) == :forbidden
      assert ResponseParser.map_http_status_to_error(404) == :not_found
      assert ResponseParser.map_http_status_to_error(429) == :rate_limited
      assert ResponseParser.map_http_status_to_error(500) == :internal_server_error
      assert ResponseParser.map_http_status_to_error(502) == :bad_gateway
      assert ResponseParser.map_http_status_to_error(503) == :service_unavailable
    end

    test "returns tuple for unknown status codes" do
      assert ResponseParser.map_http_status_to_error(418) == {:http_error, 418}
      assert ResponseParser.map_http_status_to_error(999) == {:http_error, 999}
    end
  end

  describe "parse_json_body/1" do
    test "parses valid JSON string" do
      assert {:ok, %{"key" => "value"}} = ResponseParser.parse_json_body(~s({"key": "value"}))
      assert {:ok, [1, 2, 3]} = ResponseParser.parse_json_body("[1, 2, 3]")
    end

    test "handles invalid JSON" do
      assert {:error, :invalid_json} = ResponseParser.parse_json_body("invalid json")
      assert {:error, :invalid_json} = ResponseParser.parse_json_body("{incomplete")
    end

    test "handles empty response" do
      assert {:error, :empty_response} = ResponseParser.parse_json_body("")
    end

    test "handles non-binary input" do
      assert {:error, :invalid_response} = ResponseParser.parse_json_body(nil)
      assert {:error, :invalid_response} = ResponseParser.parse_json_body(123)
      assert {:error, :invalid_response} = ResponseParser.parse_json_body(%{})
    end
  end

  describe "normalize_response/1" do
    test "normalizes successful responses (200-299)" do
      response = %{status: 200, body: ~s({"data": "success"})}
      assert {:ok, %{"data" => "success"}} = ResponseParser.normalize_response(response)

      response = %{status: 201, body: ~s({"created": true})}
      assert {:ok, %{"created" => true}} = ResponseParser.normalize_response(response)
    end

    test "handles error responses with JSON body" do
      response = %{status: 400, body: ~s({"error": "bad request"})}
      assert {:error, %{"error" => "bad request"}} = ResponseParser.normalize_response(response)

      response = %{status: 500, body: ~s({"message": "internal error"})}
      assert {:error, %{"message" => "internal error"}} = ResponseParser.normalize_response(response)
    end

    test "handles HTML error responses" do
      html_body = "<html><body>403 Forbidden</body></html>"
      response = %{status: 403, body: html_body}

      assert {:error, {:html_error, "403 Forbidden - Access denied by server"}} =
               ResponseParser.normalize_response(response)
    end

    test "handles invalid JSON in error responses" do
      response = %{status: 500, body: "Server Error"}
      assert {:error, :internal_server_error} = ResponseParser.normalize_response(response)
    end

    test "handles invalid response format" do
      assert {:error, :invalid_response} = ResponseParser.normalize_response("invalid")
      assert {:error, :invalid_response} = ResponseParser.normalize_response(nil)
    end
  end

  describe "extract_rate_limit_info/1" do
    test "extracts standard rate limit headers" do
      headers = [
        {"x-ratelimit-remaining", "99"},
        {"x-ratelimit-limit", "100"},
        {"x-ratelimit-reset", "1234567890"},
        {"other-header", "value"}
      ]

      info = ResponseParser.extract_rate_limit_info(headers)
      assert info.remaining == 99
      assert info.limit == 100
      assert info.reset == 1_234_567_890
    end

    test "extracts Binance-specific rate limit headers" do
      headers = [
        {"x-mbx-used-weight", "50"},
        {"x-mbx-used-weight-1m", "75"},
        {"content-type", "application/json"}
      ]

      info = ResponseParser.extract_rate_limit_info(headers)
      assert info.weight_used == 50
      assert info.weight_used_1m == 75
    end

    test "handles integer values in headers" do
      headers = [
        {"x-ratelimit-remaining", 99},
        {"x-ratelimit-limit", 100}
      ]

      info = ResponseParser.extract_rate_limit_info(headers)
      assert info.remaining == 99
      assert info.limit == 100
    end

    test "handles missing headers" do
      assert %{} == ResponseParser.extract_rate_limit_info([])
      assert %{} == ResponseParser.extract_rate_limit_info(nil)
    end

    test "handles invalid header values" do
      headers = [
        {"x-ratelimit-remaining", "invalid"},
        {"x-ratelimit-limit", ""}
      ]

      info = ResponseParser.extract_rate_limit_info(headers)
      assert info.remaining == 0
      assert info.limit == 0
    end
  end

  describe "standardize_error_message/1" do
    test "standardizes common error messages" do
      assert ResponseParser.standardize_error_message("Account has insufficient balance") ==
               :insufficient_balance

      assert ResponseParser.standardize_error_message("INSUFFICIENT funds") ==
               :insufficient_balance

      assert ResponseParser.standardize_error_message("Invalid symbol BTCUSDT") ==
               :invalid_symbol

      assert ResponseParser.standardize_error_message("Symbol is invalid") ==
               :invalid_symbol

      assert ResponseParser.standardize_error_message("Unauthorized access") ==
               :unauthorized

      assert ResponseParser.standardize_error_message("Authentication failed") ==
               :unauthorized

      assert ResponseParser.standardize_error_message("Rate limit exceeded") ==
               :rate_limited

      assert ResponseParser.standardize_error_message("Order not found") ==
               :order_not_found

      assert ResponseParser.standardize_error_message("Invalid quantity provided") ==
               :invalid_quantity

      assert ResponseParser.standardize_error_message("Invalid price") ==
               :invalid_price

      assert ResponseParser.standardize_error_message("Signature verification failed") ==
               :signature_not_valid
    end

    test "returns exchange_error tuple for unknown messages" do
      assert {:exchange_error, "Some custom error"} =
               ResponseParser.standardize_error_message("Some custom error")
    end

    test "handles non-string input" do
      assert ResponseParser.standardize_error_message(nil) == :unknown_error
      assert ResponseParser.standardize_error_message(123) == :unknown_error
      assert ResponseParser.standardize_error_message(%{}) == :unknown_error
    end
  end

  describe "parse_html_error/2" do
    test "detects WAF blocked requests" do
      html = "<html>Request blocked by security rules</html>"

      assert {:error, {:waf_blocked, "Request blocked by WAF"}} =
               ResponseParser.parse_html_error(html, 403)
    end

    test "detects CloudFlare protection" do
      html = "<html>CloudFlare Ray ID: 12345</html>"

      assert {:error, {:cdn_error, "CloudFlare protection triggered"}} =
               ResponseParser.parse_html_error(html, 503)

      html = "<html>Checking your browser - cloudflare</html>"

      assert {:error, {:cdn_error, "CloudFlare protection triggered"}} =
               ResponseParser.parse_html_error(html, 503)
    end

    test "extracts error from standard HTML error pages" do
      html = "<!DOCTYPE html><html><body>403 Forbidden</body></html>"

      assert {:error, {:html_error, "403 Forbidden - Access denied by server"}} =
               ResponseParser.parse_html_error(html, 403)

      html = "<html>429 Too Many Requests</html>"

      assert {:error, {:html_error, "429 Too Many Requests - Rate limit exceeded"}} =
               ResponseParser.parse_html_error(html, 429)

      html = "<html>502 Bad Gateway</html>"

      assert {:error, {:html_error, "502 Bad Gateway - Server temporarily unavailable"}} =
               ResponseParser.parse_html_error(html, 502)

      html = "<html>503 Service Unavailable</html>"

      assert {:error, {:html_error, "503 Service Unavailable - Server overloaded or under maintenance"}} =
               ResponseParser.parse_html_error(html, 503)
    end

    test "handles generic HTML error pages" do
      html = "<html><body>Error occurred</body></html>"

      assert {:error, {:html_error, "404 Not Found - Endpoint not found"}} =
               ResponseParser.parse_html_error(html, 404)

      assert {:error, {:html_error, "Server error - 500"}} =
               ResponseParser.parse_html_error(html, 500)

      assert {:error, {:html_error, "Client error - 400"}} =
               ResponseParser.parse_html_error(html, 400)
    end

    test "handles non-HTML responses" do
      assert {:error, :not_found} = ResponseParser.parse_html_error("plain text", 404)
      assert {:error, :internal_server_error} = ResponseParser.parse_html_error("", 500)
      assert {:error, {:http_error, 418}} = ResponseParser.parse_html_error(nil, 418)
    end
  end

  describe "validate_required_fields/2" do
    test "validates presence of required fields" do
      response = %{"symbol" => "BTCUSDT", "price" => "50000", "quantity" => "0.1"}

      assert :ok = ResponseParser.validate_required_fields(response, ["symbol", "price"])
      assert :ok = ResponseParser.validate_required_fields(response, ["symbol", "price", "quantity"])
      assert :ok = ResponseParser.validate_required_fields(response, [])
    end

    test "returns error for missing fields" do
      response = %{"symbol" => "BTCUSDT"}

      assert {:error, {:missing_fields, ["price"]}} =
               ResponseParser.validate_required_fields(response, ["symbol", "price"])

      assert {:error, {:missing_fields, ["price", "quantity"]}} =
               ResponseParser.validate_required_fields(response, ["symbol", "price", "quantity"])
    end

    test "handles invalid input" do
      assert {:error, :invalid_format} =
               ResponseParser.validate_required_fields("not a map", ["field"])

      assert {:error, :invalid_format} =
               ResponseParser.validate_required_fields(%{}, nil)

      assert {:error, :invalid_format} =
               ResponseParser.validate_required_fields(nil, ["field"])
    end
  end

  describe "log_error_response/2" do
    test "logs error responses without crashing" do
      # These should not raise errors
      assert :ok = ResponseParser.log_error_response(%{"error" => "test"}, "TestExchange")
      assert :ok = ResponseParser.log_error_response("string error", "TestExchange")
      assert :ok = ResponseParser.log_error_response(nil, "TestExchange")
      assert :ok = ResponseParser.log_error_response(%{"code" => -1121}, "Binance")
    end

    test "uses default exchange name when not provided" do
      assert :ok = ResponseParser.log_error_response(%{"error" => "test"})
    end
  end
end
