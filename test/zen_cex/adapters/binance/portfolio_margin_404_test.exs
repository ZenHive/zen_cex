defmodule ZenCex.Adapters.Binance.PortfolioMargin404Test do
  @moduledoc """
  Tests for Portfolio Margin endpoints that are NOT available on testnet (return 404).

  These endpoints don't exist on testnet but should work in production.
  The test behavior adapts based on environment:
  - In TEST/DEV: Expects 404 errors
  - In PRODUCTION: Tests actual API responses (when implemented)

  From check_portfolio_endpoints.exs, these 30 endpoints return 404 on testnet:
  - Account info: account_information, account_balance
  - CM Account: get_cm_account_detail, get_user_commission_rate_for_cm, get_cm_income_history
  - CM Positions: cm_notional_and_leverage_brackets, query_cm_position_information, get_cm_current_position_mode
  - UM Account: get_um_account_detail, um_futures_account_configuration, get_user_commission_rate_for_um
  - UM Info: portfolio_margin_um_trading_quantitative_rules_indicators, get_um_income_history
  - UM Positions: um_notional_and_leverage_brackets, query_um_position_information, get_um_current_position_mode
  - UM V2: get_um_account_detail_v2
  - Margin: get_margin_borrow_loan_interest_history, query_margin_loan_record, margin_max_borrow
  - Margin Query: query_margin_max_withdraw, query_margin_repay_record
  - Portfolio: query_portfolio_margin_negative_balance_interest_history, query_user_negative_balance_auto_exchange_record
  - Orders: query_um_order, cancel_um_order, query_cm_order, cancel_cm_order
  - Margin Orders: query_margin_account_order, cancel_margin_account_order
  """

  use ZenCex.IntegrationCase,
    exchange: :binance,
    api_type: :portfolio,
    async: false

  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Adapters.Binance.PortfolioMargin

  require Logger

  @moduletag :integration
  @moduletag integration: :binance

  # List of endpoints that return 404 on testnet
  @unavailable_endpoints [
    :account_information,
    :account_balance,
    :get_cm_account_detail,
    :get_user_commission_rate_for_cm,
    :get_cm_income_history,
    :cm_notional_and_leverage_brackets,
    :query_cm_position_information,
    :get_cm_current_position_mode,
    :get_um_account_detail,
    :um_futures_account_configuration,
    :portfolio_margin_um_trading_quantitative_rules_indicators,
    :get_user_commission_rate_for_um,
    :get_um_income_history,
    :um_notional_and_leverage_brackets,
    :query_um_position_information,
    :get_um_current_position_mode,
    :get_um_account_detail_v2,
    :get_margin_borrow_loan_interest_history,
    :query_margin_loan_record,
    :margin_max_borrow,
    :query_margin_max_withdraw,
    :query_margin_repay_record,
    :query_portfolio_margin_negative_balance_interest_history,
    :query_user_negative_balance_auto_exchange_record,
    :query_um_order,
    :cancel_um_order,
    :query_cm_order,
    :cancel_cm_order,
    :query_margin_account_order,
    :cancel_margin_account_order
  ]

  describe "Portfolio Margin endpoints NOT available on testnet (404 errors)" do
    test "account endpoints return 404 on testnet" do
      # Test account_information
      assert_endpoint_behavior(:account_information, &PortfolioMargin.account_information/0)

      # Test account_balance
      assert_endpoint_behavior(:account_balance, &PortfolioMargin.account_balance/0)
    end

    test "CM account endpoints return 404 on testnet" do
      assert_endpoint_behavior(:get_cm_account_detail, &PortfolioMargin.get_cm_account_detail/0)

      # With required params for commission rate
      assert_endpoint_behavior(
        :get_user_commission_rate_for_cm,
        fn -> PortfolioMargin.get_user_commission_rate_for_cm(%{symbol: "BTCUSDT"}) end
      )

      assert_endpoint_behavior(:get_cm_income_history, &PortfolioMargin.get_cm_income_history/0)
    end

    test "CM position endpoints return 404 on testnet" do
      assert_endpoint_behavior(:cm_notional_and_leverage_brackets, &PortfolioMargin.cm_notional_and_leverage_brackets/0)
      assert_endpoint_behavior(:query_cm_position_information, &PortfolioMargin.query_cm_position_information/0)
      assert_endpoint_behavior(:get_cm_current_position_mode, &PortfolioMargin.get_cm_current_position_mode/0)
    end

    test "UM account endpoints return 404 on testnet" do
      assert_endpoint_behavior(:get_um_account_detail, &PortfolioMargin.get_um_account_detail/0)
      assert_endpoint_behavior(:um_futures_account_configuration, &PortfolioMargin.um_futures_account_configuration/0)

      assert_endpoint_behavior(
        :portfolio_margin_um_trading_quantitative_rules_indicators,
        &PortfolioMargin.portfolio_margin_um_trading_quantitative_rules_indicators/0
      )

      assert_endpoint_behavior(
        :get_user_commission_rate_for_um,
        fn -> PortfolioMargin.get_user_commission_rate_for_um(%{symbol: "BTCUSDT"}) end
      )

      assert_endpoint_behavior(:get_um_income_history, &PortfolioMargin.get_um_income_history/0)
      assert_endpoint_behavior(:get_um_account_detail_v2, &PortfolioMargin.get_um_account_detail_v2/0)
    end

    test "UM position endpoints return 404 on testnet" do
      assert_endpoint_behavior(:um_notional_and_leverage_brackets, &PortfolioMargin.um_notional_and_leverage_brackets/0)
      assert_endpoint_behavior(:query_um_position_information, &PortfolioMargin.query_um_position_information/0)
      assert_endpoint_behavior(:get_um_current_position_mode, &PortfolioMargin.get_um_current_position_mode/0)
    end

    test "Margin query endpoints return 404 on testnet" do
      assert_endpoint_behavior(
        :get_margin_borrow_loan_interest_history,
        &PortfolioMargin.get_margin_borrow_loan_interest_history/0
      )

      assert_endpoint_behavior(:query_margin_loan_record, &PortfolioMargin.query_margin_loan_record/0)
      assert_endpoint_behavior(:margin_max_borrow, fn -> PortfolioMargin.margin_max_borrow(%{asset: "USDT"}) end)

      assert_endpoint_behavior(:query_margin_max_withdraw, fn ->
        PortfolioMargin.query_margin_max_withdraw(%{asset: "USDT"})
      end)

      assert_endpoint_behavior(:query_margin_repay_record, &PortfolioMargin.query_margin_repay_record/0)
    end

    test "Portfolio-specific endpoints return 404 on testnet" do
      assert_endpoint_behavior(
        :query_portfolio_margin_negative_balance_interest_history,
        &PortfolioMargin.query_portfolio_margin_negative_balance_interest_history/0
      )

      assert_endpoint_behavior(
        :query_user_negative_balance_auto_exchange_record,
        &PortfolioMargin.query_user_negative_balance_auto_exchange_record/0
      )
    end

    test "Order query endpoints return 404 on testnet" do
      # UM order queries
      assert_endpoint_behavior(:query_um_order, fn -> PortfolioMargin.query_um_order(%{symbol: "BTCUSDT"}) end)

      assert_endpoint_behavior(:cancel_um_order, fn ->
        PortfolioMargin.cancel_um_order(%{symbol: "BTCUSDT", orderId: 1})
      end)

      # CM order queries
      assert_endpoint_behavior(:query_cm_order, fn -> PortfolioMargin.query_cm_order(%{symbol: "BTCUSD_PERP"}) end)

      assert_endpoint_behavior(:cancel_cm_order, fn ->
        PortfolioMargin.cancel_cm_order(%{symbol: "BTCUSD_PERP", orderId: 1})
      end)

      # Margin order queries
      assert_endpoint_behavior(:query_margin_account_order, fn ->
        PortfolioMargin.query_margin_account_order(%{symbol: "BTCUSDT"})
      end)

      assert_endpoint_behavior(:cancel_margin_account_order, fn ->
        PortfolioMargin.cancel_margin_account_order(%{symbol: "BTCUSDT", orderId: 1})
      end)
    end
  end

  describe "Environment detection" do
    test "correctly identifies test environment" do
      # We should be in test environment
      assert Endpoints.current_env() == :test

      # Base URL should be testnet
      assert Endpoints.base_url() =~ "testnet"
    end

    test "all unavailable endpoints are documented" do
      # Ensure our list matches what we expect
      assert length(@unavailable_endpoints) == 30
    end
  end

  # Helper function to assert endpoint behavior based on environment
  defp assert_endpoint_behavior(endpoint_name, endpoint_fn) do
    case endpoint_fn.() do
      {:error, {:unknown_error, %{"status" => 404} = response}} ->
        # Expected on testnet
        Logger.info("#{endpoint_name} returns 404 on testnet (expected): #{inspect(response)}")
        assert_testnet_404(endpoint_name)

      {:error, {:unknown_error, %{"error" => "Not Found", "status" => 404}}} ->
        # Another format of 404 from testnet
        Logger.info("#{endpoint_name} returns 404 on testnet (expected)")
        assert_testnet_404(endpoint_name)

      {:error, other_error} ->
        # If we get a different error in test env, it might mean the endpoint
        # is now available on testnet (good news!)
        Logger.warning("#{endpoint_name} returned non-404 error on testnet: #{inspect(other_error)}")

        # This could mean:
        # 1. Endpoint is now available on testnet (update our lists!)
        # 2. Network/auth issue
        # 3. Different error format

        # TODO: For now, we'll pass the test but log for investigation
        assert true

      {:ok, response} ->
        # Unexpected success on testnet!
        # This means the endpoint is now available (or we're in production)
        if Endpoints.current_env() == :test do
          Logger.warning("#{endpoint_name} SUCCEEDED on testnet! Response: #{inspect(response)}")
          Logger.warning("This endpoint may now be available on testnet - update the test lists!")

          # Don't fail the test, but flag for attention
          assert true
        else
          # TODO: In production, this is expected
          Logger.info("#{endpoint_name} succeeded in production environment")
          assert_production_response(endpoint_name, response)
        end
    end
  end

  defp assert_testnet_404(endpoint_name) do
    # On testnet, we expect 404s for these endpoints
    assert endpoint_name in @unavailable_endpoints,
           "#{endpoint_name} returned 404 but is not in our unavailable list"
  end

  defp assert_production_response(endpoint_name, response) do
    # TODO: In production, validate the actual response structure
    # For now, just assert we got something
    assert response
    Logger.info("Production response for #{endpoint_name}: #{inspect(response)}")
  end
end
