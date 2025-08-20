defmodule ZenCex.Adapters.Binance.ProductDetectorTest do
  @moduledoc """
  Tests for Binance product type detection from symbols and parameters.
  """

  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.ProductDetector

  describe "detect/1" do
    test "detects from explicit product_type parameter" do
      assert ProductDetector.detect(%{product_type: "UM"}) == :um_futures
      assert ProductDetector.detect(%{product_type: "CM"}) == :cm_futures
      assert ProductDetector.detect(%{product_type: "MARGIN"}) == :margin
      assert ProductDetector.detect(%{product_type: "INVALID"}) == :unknown
    end

    test "detects from symbol when no product_type given" do
      assert ProductDetector.detect(%{symbol: "BTCUSDT"}) == :um_futures
      assert ProductDetector.detect(%{symbol: "BTCUSD_PERP"}) == :cm_futures
      assert ProductDetector.detect(%{symbol: "ETHBTC"}) == :margin
    end

    test "prefers explicit product_type over symbol" do
      # Even though BTCUSDT normally indicates UM futures,
      # explicit product_type takes precedence
      assert ProductDetector.detect(%{symbol: "BTCUSDT", product_type: "MARGIN"}) == :margin
    end

    test "returns unknown for empty params" do
      assert ProductDetector.detect(%{}) == :unknown
      assert ProductDetector.detect(nil) == :unknown
    end
  end

  describe "detect_from_symbol/1" do
    test "detects USD-M futures symbols" do
      # Perpetuals
      assert ProductDetector.detect_from_symbol("BTCUSDT") == :um_futures
      assert ProductDetector.detect_from_symbol("ETHUSDT") == :um_futures
      assert ProductDetector.detect_from_symbol("BNBUSDT") == :um_futures

      # With BUSD
      assert ProductDetector.detect_from_symbol("BTCBUSD") == :um_futures
      assert ProductDetector.detect_from_symbol("ETHBUSD") == :um_futures

      # Case insensitive
      assert ProductDetector.detect_from_symbol("btcusdt") == :um_futures
    end

    test "detects COIN-M futures symbols" do
      # Perpetuals
      assert ProductDetector.detect_from_symbol("BTCUSD_PERP") == :cm_futures
      assert ProductDetector.detect_from_symbol("ETHUSD_PERP") == :cm_futures

      # Quarterly
      assert ProductDetector.detect_from_symbol("BTCUSD_240329") == :cm_futures
      assert ProductDetector.detect_from_symbol("BTCUSD_QUARTER") == :cm_futures
      assert ProductDetector.detect_from_symbol("ETHUSD_CURRENT_QUARTER") == :cm_futures

      # Case insensitive
      assert ProductDetector.detect_from_symbol("btcusd_perp") == :cm_futures
    end

    test "detects margin trading symbols" do
      # Standard pairs
      assert ProductDetector.detect_from_symbol("ETHBTC") == :margin
      assert ProductDetector.detect_from_symbol("BNBETH") == :margin
      assert ProductDetector.detect_from_symbol("LTCBTC") == :margin
      assert ProductDetector.detect_from_symbol("XRPBTC") == :margin

      # Case insensitive
      assert ProductDetector.detect_from_symbol("ethbtc") == :margin
    end
  end

  describe "detect_from_product_type/1" do
    test "detects valid product types" do
      assert ProductDetector.detect_from_product_type("UM") == :um_futures
      assert ProductDetector.detect_from_product_type("CM") == :cm_futures
      assert ProductDetector.detect_from_product_type("MARGIN") == :margin
    end

    test "case insensitive" do
      assert ProductDetector.detect_from_product_type("um") == :um_futures
      assert ProductDetector.detect_from_product_type("Um") == :um_futures
      assert ProductDetector.detect_from_product_type("margin") == :margin
    end

    test "returns unknown for invalid types" do
      assert ProductDetector.detect_from_product_type("SPOT") == :unknown
      assert ProductDetector.detect_from_product_type("INVALID") == :unknown
      assert ProductDetector.detect_from_product_type("") == :unknown
    end
  end

  describe "validate_symbol/1" do
    test "validates USD-M futures symbols" do
      assert {:ok, :um_futures} = ProductDetector.validate_symbol("BTCUSDT")
      assert {:ok, :um_futures} = ProductDetector.validate_symbol("ETHBUSD")
    end

    test "validates COIN-M futures symbols" do
      assert {:ok, :cm_futures} = ProductDetector.validate_symbol("BTCUSD_PERP")
      assert {:ok, :cm_futures} = ProductDetector.validate_symbol("BTCUSD_240329")
      assert {:ok, :cm_futures} = ProductDetector.validate_symbol("ETHUSD_QUARTER")
    end

    test "validates margin symbols" do
      assert {:ok, :margin} = ProductDetector.validate_symbol("ETHBTC")
      assert {:ok, :margin} = ProductDetector.validate_symbol("BNBETH")
    end

    test "rejects invalid symbols" do
      assert {:error, _} = ProductDetector.validate_symbol("INVALID_SYMBOL_FORMAT")
      assert {:error, _} = ProductDetector.validate_symbol("123456")
      assert {:error, _} = ProductDetector.validate_symbol("")
    end
  end

  describe "get_endpoint_module/1" do
    test "returns correct module for each product type" do
      assert ProductDetector.get_endpoint_module(:um_futures) == ZenCex.Adapters.Binance.UsdmFutures
      assert ProductDetector.get_endpoint_module(:cm_futures) == ZenCex.Adapters.Binance.CoinmFutures
      assert ProductDetector.get_endpoint_module(:margin) == ZenCex.Adapters.Binance.Spot
      assert ProductDetector.get_endpoint_module(:unknown) == nil
    end
  end
end
