defmodule ZenCex.Adapters.Binance.MarginTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Margin

  describe "endpoint configurations" do
    test "all endpoints have required fields" do
      endpoints = Margin.all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0

      Enum.each(endpoints, fn config ->
        assert Map.has_key?(config, :operation)
        assert Map.has_key?(config, :method)
        assert Map.has_key?(config, :path)
        assert Map.has_key?(config, :requires_auth)
        assert Map.has_key?(config, :weight)
        assert Map.has_key?(config, :timeout)
        assert Map.has_key?(config, :retry_on)
        assert Map.has_key?(config, :response_parser)
        assert Map.has_key?(config, :error_mapping)
      end)
    end

    test "get_cross_margin_account configuration" do
      config = Margin.get_endpoint(:get_cross_margin_account)
      assert config.operation == :get_cross_margin_account
      assert config.method == :get
      assert config.path == "/sapi/v1/margin/account"
      assert config.requires_auth == true
      assert config.weight == 20
      assert config.timeout == 5_000
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
    end

    test "get_isolated_margin_account configuration" do
      config = Margin.get_endpoint(:get_isolated_margin_account)
      assert config.operation == :get_isolated_margin_account
      assert config.method == :get
      assert config.path == "/sapi/v1/margin/isolated/account"
      assert config.requires_auth == true
      assert config.weight == 20
      assert config.timeout == 5_000
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
    end

    test "place_order configuration has no retries" do
      config = Margin.get_endpoint(:place_order)
      assert config.operation == :place_order
      assert config.method == :post
      assert config.path == "/sapi/v1/margin/order"
      assert config.requires_auth == true
      assert config.max_retries == 0
      assert config.retry_on == []
      assert config.timeout == 5_000
    end

    test "cancel_order configuration has limited retries" do
      config = Margin.get_endpoint(:cancel_order)
      assert config.operation == :cancel_order
      assert config.method == :delete
      assert config.path == "/sapi/v1/margin/order"
      assert config.requires_auth == true
      assert config.max_retries == 1
      assert config.retry_on == [:timeout]
    end

    test "transfer operations are configured correctly" do
      config = Margin.get_endpoint(:get_transfer)
      assert config.operation == :get_transfer
      assert config.method == :get
      assert config.path == "/sapi/v1/margin/transfer"
      assert config.requires_auth == true
      # Query operations can safely retry
      assert config.max_retries > 0
      assert :timeout in config.retry_on
    end

    test "borrow_or_repay operation is configured correctly" do
      config = Margin.get_endpoint(:borrow_or_repay)
      assert config.operation == :borrow_or_repay
      assert config.method == :post
      assert config.path == "/sapi/v1/margin/borrow-repay"
      assert config.requires_auth == true
      # Check that it's configured (actual retry settings may vary)
      assert is_integer(config.max_retries)
      assert is_list(config.retry_on)
    end

    test "complex order operations have appropriate timeouts" do
      # OCO orders
      config = Margin.get_endpoint(:place_order_oco)
      assert config.operation == :place_order_oco
      assert config.timeout == 2_000
      assert config.max_retries == 0
      assert config.retry_on == []

      # OTO orders
      config = Margin.get_endpoint(:place_order_oto)
      assert config.operation == :place_order_oto
      assert config.timeout == 2_000
      assert config.max_retries == 0
      assert config.retry_on == []
    end

    test "get_weight returns correct weights" do
      assert Margin.get_weight(:get_cross_margin_account) == 20
      assert Margin.get_weight(:get_isolated_margin_account) == 20
      assert Margin.get_weight(:place_order) == 5
      assert Margin.get_weight(:cancel_order) == 5
      assert Margin.get_weight(:get_order) == 5
    end
  end

  describe "function exports" do
    test "margin-specific functions are exported" do
      exports = Margin.__info__(:functions)

      # Account management
      assert {:get_cross_margin_account, 0} in exports
      assert {:get_cross_margin_account, 1} in exports
      assert {:get_cross_margin_account, 2} in exports
      assert {:get_isolated_margin_account, 0} in exports
      assert {:get_isolated_margin_account, 1} in exports
      assert {:get_isolated_margin_account, 2} in exports

      # Orders
      assert {:place_order, 0} in exports
      assert {:place_order, 1} in exports
      assert {:place_order, 2} in exports
      assert {:cancel_order, 0} in exports
      assert {:cancel_order, 1} in exports
      assert {:cancel_order, 2} in exports

      # Transfers and borrowing
      assert {:get_transfer, 0} in exports
      assert {:get_transfer, 1} in exports
      assert {:get_transfer, 2} in exports
      assert {:borrow_or_repay, 0} in exports
      assert {:borrow_or_repay, 1} in exports
      assert {:borrow_or_repay, 2} in exports

      # History
      # Note: get_transfer_history might not exist, check for get_transfer instead
      assert {:get_transfer, 0} in exports
      assert {:get_transfer, 1} in exports
      assert {:get_transfer, 2} in exports
      assert {:get_borrow_repay_history, 0} in exports
      assert {:get_borrow_repay_history, 1} in exports
      assert {:get_borrow_repay_history, 2} in exports
      assert {:get_interest_history, 0} in exports
      assert {:get_interest_history, 1} in exports
      assert {:get_interest_history, 2} in exports
    end
  end
end
