defmodule ZenCex.Safety.OrderSafety.ConfigTest do
  use ExUnit.Case, async: false

  alias ZenCex.Safety.OrderSafety.Config

  describe "max_price_deviation_percent/0" do
    test "returns default value when no config set" do
      assert Config.max_price_deviation_percent() == 20
    end

    test "can be overridden by environment variable" do
      System.put_env("ORDER_SAFETY_MAX_PRICE_DEVIATION_PERCENT", "25")

      # Need to recompile module to pick up env var at compile time
      # In production, this would be set before app starts
      assert Config.max_price_deviation_percent() == 25

      System.delete_env("ORDER_SAFETY_MAX_PRICE_DEVIATION_PERCENT")
    end
  end

  describe "max_price_deviation_percent/1" do
    test "returns default for unknown exchange" do
      assert Config.max_price_deviation_percent(:unknown_exchange) == 20
    end

    test "can have exchange-specific overrides" do
      System.put_env("ORDER_SAFETY_BINANCE_MAX_PRICE_DEVIATION_PERCENT", "30")

      assert Config.max_price_deviation_percent(:binance) == 30
      # Falls back to default
      assert Config.max_price_deviation_percent(:bybit) == 20

      System.delete_env("ORDER_SAFETY_BINANCE_MAX_PRICE_DEVIATION_PERCENT")
    end
  end

  describe "idempotency_window_ms/0" do
    test "returns default 30 minutes in milliseconds" do
      assert Config.idempotency_window_ms() == 30 * 60 * 1000
    end

    test "can be overridden by environment variable" do
      System.put_env("ORDER_SAFETY_IDEMPOTENCY_WINDOW_MINUTES", "15")

      assert Config.idempotency_window_ms() == 15 * 60 * 1000

      System.delete_env("ORDER_SAFETY_IDEMPOTENCY_WINDOW_MINUTES")
    end
  end

  describe "cleanup_interval_ms/0" do
    test "returns default 60 seconds in milliseconds" do
      assert Config.cleanup_interval_ms() == 60 * 1000
    end

    test "can be overridden by environment variable" do
      System.put_env("ORDER_SAFETY_CLEANUP_INTERVAL_SECONDS", "30")

      assert Config.cleanup_interval_ms() == 30 * 1000

      System.delete_env("ORDER_SAFETY_CLEANUP_INTERVAL_SECONDS")
    end
  end

  describe "websocket_data_max_age_ms/0" do
    test "returns default 5 seconds in milliseconds" do
      assert Config.websocket_data_max_age_ms() == 5 * 1000
    end

    test "can be overridden by environment variable" do
      System.put_env("ORDER_SAFETY_WEBSOCKET_DATA_MAX_AGE_SECONDS", "10")

      assert Config.websocket_data_max_age_ms() == 10 * 1000

      System.delete_env("ORDER_SAFETY_WEBSOCKET_DATA_MAX_AGE_SECONDS")
    end
  end

  describe "default_min_notional/1" do
    test "returns exchange-specific defaults" do
      assert Config.default_min_notional(:binance) == "10.00"
      assert Config.default_min_notional(:bybit) == "1.00"
      assert Config.default_min_notional(:kraken) == "10.00"
      assert Config.default_min_notional(:deribit) == "10.00"
    end

    test "can be overridden per exchange" do
      System.put_env("ORDER_SAFETY_BINANCE_MIN_NOTIONAL", "5.00")

      assert Config.default_min_notional(:binance) == "5.00"
      # Unchanged
      assert Config.default_min_notional(:bybit) == "1.00"

      System.delete_env("ORDER_SAFETY_BINANCE_MIN_NOTIONAL")
    end

    test "returns default for unknown exchange" do
      assert Config.default_min_notional(:unknown_exchange) == "10.00"
    end
  end

  describe "cache_ttls/0" do
    test "returns TTL configuration from TimeConstants" do
      ttls = Config.cache_ttls()

      assert is_map(ttls)
      assert Map.has_key?(ttls, :price)
      assert Map.has_key?(ttls, :symbol_info)
      assert Map.has_key?(ttls, :min_notional)

      # Values should be in milliseconds
      assert ttls.price > 0
      assert ttls.symbol_info > 0
      assert ttls.min_notional > 0
    end
  end
end
