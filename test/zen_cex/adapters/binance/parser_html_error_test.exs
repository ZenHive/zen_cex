defmodule ZenCex.Adapters.Binance.ParserHtmlErrorTest do
  @moduledoc """
  Tests for HTML error parsing in Binance Parser.

  These tests verify that HTML error pages from CDN/WAF are properly
  detected and converted to meaningful error tuples.
  """
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Parser

  describe "parse_error/1 with HTML responses" do
    test "detects CloudFlare error page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>CloudFlare Protection</title></head>
      <body>CloudFlare ray ID: 12345</body>
      </html>
      """

      assert {:error, {:cdn_error, "CloudFlare protection triggered"}} = Parser.parse_error(html)
    end

    test "detects WAF blocked request" do
      html = """
      <html>
      <body>
      <h1>Request blocked</h1>
      <p>Your request has been blocked by our security system.</p>
      </body>
      </html>
      """

      assert {:error, {:waf_blocked, "Request blocked by WAF"}} = Parser.parse_error(html)
    end

    test "detects 403 Forbidden HTML page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>403 Forbidden</title></head>
      <body>
      <h1>403 Forbidden</h1>
      <p>Access denied</p>
      </body>
      </html>
      """

      assert {:error, {:html_error, "403 Forbidden - Access denied by server"}} =
               Parser.parse_error(html)
    end

    test "detects 429 Too Many Requests HTML page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>429 Too Many Requests</title></head>
      <body>
      <h1>Too Many Requests</h1>
      <p>Rate limit exceeded</p>
      </body>
      </html>
      """

      assert {:error, {:html_error, "429 Too Many Requests - Rate limit exceeded"}} =
               Parser.parse_error(html)
    end

    test "detects 502 Bad Gateway HTML page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>502 Bad Gateway</title></head>
      <body>
      <h1>502 Bad Gateway</h1>
      <p>The server is temporarily unavailable</p>
      </body>
      </html>
      """

      assert {:error, {:html_error, "502 Bad Gateway - Server temporarily unavailable"}} =
               Parser.parse_error(html)
    end

    test "detects 503 Service Unavailable HTML page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>503 Service Unavailable</title></head>
      <body>
      <h1>503 Service Unavailable</h1>
      <p>Server is under maintenance</p>
      </body>
      </html>
      """

      assert {:error, {:html_error, "503 Service Unavailable - Server overloaded or under maintenance"}} =
               Parser.parse_error(html)
    end

    test "detects generic HTML error page" do
      html = """
      <!DOCTYPE html>
      <html>
      <head><title>Error</title></head>
      <body>
      <h1>An error occurred</h1>
      </body>
      </html>
      """

      assert {:error, {:html_error, "Server returned HTML error page instead of JSON response"}} =
               Parser.parse_error(html)
    end

    test "handles HTML with uppercase DOCTYPE" do
      html = """
      <!DOCTYPE HTML>
      <HTML>
      <HEAD><TITLE>Error</TITLE></HEAD>
      <BODY>Error page</BODY>
      </HTML>
      """

      assert {:error, {:html_error, _}} = Parser.parse_error(html)
    end

    test "handles HTML without DOCTYPE" do
      html = """
      <html>
      <head><title>Error</title></head>
      <body>Error page</body>
      </html>
      """

      assert {:error, {:html_error, _}} = Parser.parse_error(html)
    end

    test "returns unknown_error for non-HTML strings" do
      assert {:error, :unknown_error} = Parser.parse_error("plain text error")
      assert {:error, :unknown_error} = Parser.parse_error("{not valid json}")
    end

    test "returns unknown_error for empty string" do
      assert {:error, :unknown_error} = Parser.parse_error("")
    end

    test "returns unknown_error for nil" do
      assert {:error, :unknown_error} = Parser.parse_error(nil)
    end
  end
end
