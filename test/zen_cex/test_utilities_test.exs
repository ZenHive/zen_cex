defmodule ZenCex.TestUtilitiesTest do
  use ExUnit.Case

  import ZenCex.TestUtilities.EnvHelpers

  alias ZenCex.TestUtilities
  alias ZenCex.TestUtilities.Generators
  alias ZenCex.TestUtilities.Validators

  describe "get_test_config!/1" do
    test "raises error with helpful message when credentials are missing" do
      with_env [{"BINANCE_TESTNET_API_KEY", nil}, {"BINANCE_TESTNET_API_SECRET", nil}] do
        assert_raise RuntimeError, ~r/Missing binance testnet credentials/, fn ->
          TestUtilities.get_test_config!(:binance)
        end
      end
    end

    test "returns config when credentials are present" do
      with_env [{"BINANCE_TESTNET_API_KEY", "test_key"}, {"BINANCE_TESTNET_API_SECRET", "test_secret"}] do
        config = TestUtilities.get_test_config!(:binance)

        assert config.api_key == "test_key"
        assert config.api_secret == "test_secret"
        assert config.testnet == true
        assert config.exchange == :binance
      end
    end
  end

  describe "maybe_get_test_config/1" do
    test "returns error tuple when credentials are missing" do
      with_env [{"BYBIT_TESTNET_API_KEY", nil}, {"BYBIT_TESTNET_API_SECRET", nil}] do
        assert {:error, message} = TestUtilities.maybe_get_test_config(:bybit)
        assert message =~ "BYBIT_TESTNET_API_KEY"
      end
    end

    test "returns ok tuple with config when credentials are present" do
      with_env [{"BYBIT_TESTNET_API_KEY", "test_key"}, {"BYBIT_TESTNET_API_SECRET", "test_secret"}] do
        assert {:ok, config} = TestUtilities.maybe_get_test_config(:bybit)
        assert config.api_key == "test_key"
        assert config.api_secret == "test_secret"
        assert config.testnet == true
        assert config.exchange == :bybit
      end
    end

    test "handles OKX with passphrase requirement" do
      # Missing passphrase
      with_env [
        {"OKX_TESTNET_API_KEY", "test_key"},
        {"OKX_TESTNET_API_SECRET", "test_secret"},
        {"OKX_TESTNET_PASSPHRASE", nil}
      ] do
        assert {:error, message} = TestUtilities.maybe_get_test_config(:okx)
        assert message =~ "OKX_TESTNET_PASSPHRASE"
      end

      # With passphrase
      with_env [
        {"OKX_TESTNET_API_KEY", "test_key"},
        {"OKX_TESTNET_API_SECRET", "test_secret"},
        {"OKX_TESTNET_PASSPHRASE", "test_passphrase"}
      ] do
        assert {:ok, config} = TestUtilities.maybe_get_test_config(:okx)
        assert config.passphrase == "test_passphrase"
      end
    end
  end

  describe "get_binance_futures_test_config!/0" do
    test "uses different environment variables for futures" do
      with_env [
        {"BINANCE_FUTURES_TEST_API_KEY", "futures_key"},
        {"BINANCE_FUTURES_TEST_API_SECRET", "futures_secret"}
      ] do
        config = TestUtilities.get_binance_futures_test_config!()

        assert config.api_key == "futures_key"
        assert config.api_secret == "futures_secret"
        assert config.testnet == true
        assert config.exchange == :binance
      end
    end

    test "raises when futures credentials are missing" do
      with_env [{"BINANCE_FUTURES_TEST_API_KEY", nil}, {"BINANCE_FUTURES_TEST_API_SECRET", nil}] do
        assert_raise RuntimeError, ~r/Missing Binance futures testnet credentials/, fn ->
          TestUtilities.get_binance_futures_test_config!()
        end
      end
    end
  end

  describe "get_invalid_config/2" do
    test "generates invalid config for testing error cases" do
      config = TestUtilities.get_invalid_config(:binance, :spot)

      assert config.api_key == "invalid_api_key_binance"
      assert config.api_secret == "invalid_api_secret_binance"
      assert config.testnet == true
      assert config.exchange == :binance
      assert config.account_type == :spot
    end

    test "defaults to spot account type" do
      config = TestUtilities.get_invalid_config(:bybit)
      assert config.account_type == :spot
    end
  end

  describe "with_account_type/2" do
    test "adds account type to existing config" do
      config = %{api_key: "key", api_secret: "secret"}
      updated = TestUtilities.with_account_type(config, :futures_usdm)

      assert updated.account_type == :futures_usdm
      assert updated.api_key == "key"
    end
  end

  describe "should_run_api_tests?/1" do
    test "returns false when credentials are missing" do
      with_env [{"DERIBIT_TESTNET_API_KEY", nil}, {"DERIBIT_TESTNET_API_SECRET", nil}] do
        refute TestUtilities.should_run_api_tests?(:deribit)
      end
    end

    test "returns true when credentials are present" do
      with_env [{"DERIBIT_TESTNET_API_KEY", "key"}, {"DERIBIT_TESTNET_API_SECRET", "secret"}] do
        assert TestUtilities.should_run_api_tests?(:deribit)
      end
    end
  end

  describe "should_run_api_tests?/0" do
    test "returns false in CI environment" do
      with_env [{"CI", "true"}] do
        refute TestUtilities.should_run_api_tests?()
      end
    end

    test "returns true when any exchange has credentials" do
      with_env [
        {"CI", nil},
        {"BINANCE_TESTNET_API_KEY", "key"},
        {"BINANCE_TESTNET_API_SECRET", "secret"}
      ] do
        assert TestUtilities.should_run_api_tests?()
      end
    end

    test "returns false when no exchange has credentials" do
      with_env [
        {"CI", nil},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", nil},
        {"BYBIT_TESTNET_API_KEY", nil},
        {"BYBIT_TESTNET_API_SECRET", nil},
        {"DERIBIT_TESTNET_API_KEY", nil},
        {"DERIBIT_TESTNET_API_SECRET", nil},
        {"OKX_TESTNET_API_KEY", nil},
        {"OKX_TESTNET_API_SECRET", nil},
        {"OKX_TESTNET_PASSPHRASE", nil}
      ] do
        refute TestUtilities.should_run_api_tests?()
      end
    end
  end

  describe "assertion helpers" do
    test "assert_ok returns value on success" do
      assert TestUtilities.assert_ok({:ok, "value"}) == "value"
    end

    test "assert_ok raises on non-ok tuple" do
      assert_raise RuntimeError, ~r/Expected \{:ok, value\}/, fn ->
        TestUtilities.assert_ok({:error, "reason"})
      end
    end

    test "assert_error returns reason on error" do
      assert TestUtilities.assert_error({:error, "reason"}) == "reason"
    end

    test "assert_error raises on non-error tuple" do
      assert_raise RuntimeError, ~r/Expected \{:error, reason\}/, fn ->
        TestUtilities.assert_error({:ok, "value"})
      end
    end
  end

  describe "environment cache management" do
    test "clear_environment_cache handles non-existent keys gracefully" do
      # Should not raise
      assert TestUtilities.clear_environment_cache(NonExistentModule) == :ok
    end

    test "clear_all_environment_caches clears known modules" do
      # Should not raise even if modules aren't loaded
      assert TestUtilities.clear_all_environment_caches() == :ok
    end
  end

  describe "Generators" do
    test "generate_test_balance creates exchange-specific formats" do
      # Binance format
      balance = Generators.generate_test_balance(:binance, "BTC", "1.5", "0.5")
      assert balance["asset"] == "BTC"
      assert balance["free"] == "1.5"
      assert balance["locked"] == "0.5"

      # Bybit format
      balance = Generators.generate_test_balance(:bybit, "ETH", "10", "2")
      assert balance["coin"] == "ETH"
      assert balance["free"] == "10"
      assert balance["locked"] == "2"
      assert balance["walletBalance"] == "12.0"
    end

    test "generate_test_position creates exchange-specific formats" do
      # Binance position
      position = Generators.generate_test_position(:binance, "BTCUSDT", "LONG", "0.5", "40000", "41000")
      assert position["symbol"] == "BTCUSDT"
      assert position["positionSide"] == "LONG"
      assert position["positionAmt"] == "0.5"
      assert position["entryPrice"] == "40000"
      assert position["markPrice"] == "41000"

      # Bybit position
      position = Generators.generate_test_position(:bybit, "ETHUSDT", "BUY", "2", "2000", "2100")
      assert position["symbol"] == "ETHUSDT"
      assert position["side"] == "Buy"
      assert position["size"] == "2"
      assert position["avgPrice"] == "2000"
      assert position["markPrice"] == "2100"
    end

    test "generate_test_order creates exchange-specific formats" do
      # Binance order
      order = Generators.generate_test_order(:binance, "BTCUSDT", "BUY", "LIMIT", "0.1", "40000")
      assert order["symbol"] == "BTCUSDT"
      assert order["side"] == "BUY"
      assert order["type"] == "LIMIT"
      assert order["origQty"] == "0.1"
      assert order["price"] == "40000"
      assert is_binary(order["orderId"]) or is_integer(order["orderId"])

      # Bybit order
      order = Generators.generate_test_order(:bybit, "ETHUSDT", "SELL", "MARKET", "1", "0")
      assert order["symbol"] == "ETHUSDT"
      assert order["side"] == "Sell"
      assert order["orderType"] == "Market"
      assert order["qty"] == "1"
    end

    test "generate_test_kline creates exchange-specific formats" do
      timestamp = 1_640_000_000_000

      # Binance kline (12 elements)
      kline = Generators.generate_test_kline(:binance, timestamp, "40000", "41000", "39000", "40500", "100")
      assert is_list(kline)
      assert length(kline) == 12
      assert Enum.at(kline, 0) == timestamp
      assert Enum.at(kline, 1) == "40000"

      # Bybit kline (7 elements)
      kline = Generators.generate_test_kline(:bybit, timestamp, "2000", "2100", "1900", "2050", "500")
      assert is_list(kline)
      assert length(kline) == 7
      assert Enum.at(kline, 0) == "#{timestamp}"
      assert Enum.at(kline, 1) == "2000"
    end

    test "generate_test_ticker creates exchange-specific formats" do
      # Binance ticker
      ticker = Generators.generate_test_ticker(:binance, "BTCUSDT", "40000")
      assert ticker["symbol"] == "BTCUSDT"
      assert ticker["price"] == "40000"

      # Bybit ticker
      ticker = Generators.generate_test_ticker(:bybit, "ETHUSDT", "2000")
      assert ticker["symbol"] == "ETHUSDT"
      assert ticker["lastPrice"] == "2000"
      assert ticker["indexPrice"] == "2000"
      assert ticker["markPrice"] == "2000"
    end

    test "generate_test_funding_rate creates exchange-specific formats" do
      # Binance funding
      funding = Generators.generate_test_funding_rate(:binance, "BTCUSDT", "0.0001")
      assert funding["symbol"] == "BTCUSDT"
      assert funding["fundingRate"] == "0.0001"
      assert is_integer(funding["fundingTime"])

      # Bybit funding
      funding = Generators.generate_test_funding_rate(:bybit, "ETHUSDT", "0.0002")
      assert funding["symbol"] == "ETHUSDT"
      assert funding["fundingRate"] == "0.0002"
      assert is_binary(funding["nextFundingTime"])
    end
  end

  describe "Validators" do
    test "assert_valid_balance_structure validates Binance format" do
      valid_balance = %{
        "asset" => "BTC",
        "free" => "1.0",
        "locked" => "0.5"
      }

      # Should not raise
      assert Validators.assert_valid_balance_structure(valid_balance, :binance) == :ok

      # Should also work with list
      assert Validators.assert_valid_balance_structure([valid_balance], :binance) == :ok
    end

    test "assert_valid_position_structure validates Bybit format" do
      valid_position = %{
        "symbol" => "BTCUSDT",
        "side" => "Buy",
        "size" => "1.0",
        "avgPrice" => "40000",
        "markPrice" => "41000"
      }

      # Should not raise
      assert Validators.assert_valid_position_structure(valid_position, :bybit) == :ok
    end

    test "assert_valid_order_structure validates exchange formats" do
      binance_order = %{
        "symbol" => "BTCUSDT",
        "orderId" => 123_456,
        "clientOrderId" => "test123",
        "price" => "40000",
        "origQty" => "0.1",
        "status" => "NEW",
        "type" => "LIMIT",
        "side" => "BUY"
      }

      assert Validators.assert_valid_order_structure(binance_order, :binance) == :ok
    end

    test "assert_valid_kline_structure validates kline arrays" do
      # Binance kline with 12 elements
      binance_kline = [
        # timestamp
        1_640_000_000_000,
        # open
        "40000",
        # high
        "41000",
        # low
        "39000",
        # close
        "40500",
        # volume
        "100",
        # close time
        1_640_000_059_999,
        # quote volume
        "4050000",
        # trades
        500,
        # taker buy base
        "50",
        # taker buy quote
        "2025000",
        # ignore
        "0"
      ]

      assert Validators.assert_valid_kline_structure([binance_kline], :binance) == :ok
    end
  end
end
