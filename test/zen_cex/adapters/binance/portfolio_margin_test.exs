defmodule ZenCex.Adapters.Binance.PortfolioMarginTest do
  @moduledoc """
  Tests for Portfolio Margin trading endpoints.

  ⚠️  REQUIRES PRODUCTION PORTFOLIO MARGIN CREDENTIALS ⚠️

  Portfolio Margin has NO TESTNET - always uses production API (https://papi.binance.com)

  Current Status: Tests expect auth/permission errors because PM credentials not configured

  To enable full testing:
  1. Set up production Portfolio Margin API key/secret with PM permissions
  2. Configure environment variables (see IntegrationCase)
  3. Ensure IP is whitelisted
  4. Tests will use safety measures:
     * Read-only operations test actual responses
     * Write operations use minimal amounts (0.001 BTC, $1 USDT)
     * Orders use limit prices far from market to avoid execution

  Without PM credentials, tests pass but only verify error handling.
  """

  use ZenCex.IntegrationCase,
    exchange: :binance,
    api_type: :portfolio,
    use_production_for_test: true,
    async: false

  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Adapters.Binance.PortfolioMargin

  require Logger

  @moduletag :integration
  @moduletag integration: :binance

  describe "Portfolio Margin trading endpoints" do
    test "change_um_initial_leverage handles based on environment", %{api_key: api_key, api_secret: api_secret} do
      # Portfolio Margin uses production API
      # Test expects either success or specific production errors
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.change_um_initial_leverage(%{symbol: "BTCUSDT", leverage: 1}, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "change_cm_initial_leverage requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.change_cm_initial_leverage(%{}, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "change_um_position_mode requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.change_um_position_mode(%{}, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "change_cm_position_mode requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.change_cm_position_mode(%{}, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "new_um_order with safety measures", %{api_key: api_key, api_secret: api_secret} do
      # SAFETY: Use limit order with price far from market
      # This ensures order won't execute even in production
      safe_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        # Minimal amount
        quantity: "0.001",
        # Far below market price (~$100k)
        price: "10000",
        timeInForce: "GTC"
      }

      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      # Portfolio Margin uses production API - test with far-from-market price for safety
      case PortfolioMargin.new_um_order(safe_params, opts) do
        {:ok, order} ->
          # Success - immediately cancel for safety
          Logger.info("Portfolio Margin: Order placed: #{inspect(order)}")

          # Try to cancel immediately
          if order["orderId"] do
            cancel_result =
              PortfolioMargin.cancel_um_order(
                %{
                  symbol: "BTCUSDT",
                  orderId: order["orderId"]
                },
                opts
              )

            Logger.info("Cancel result: #{inspect(cancel_result)}")
          end

          assert is_map(order)

        {:error, reason} ->
          assert_pm_success_or_not_configured({:error, reason})
      end
    end

    test "new_cm_order requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      params = %{symbol: "INVALID"}
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.new_cm_order(params, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "new_margin_order requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      params = %{symbol: "INVALID"}
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.new_margin_order(params, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "margin_account_borrow requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.margin_account_borrow(%{}, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "margin_account_repay requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.margin_account_repay(%{}, opts)
      assert_pm_success_or_not_configured(result)
    end

    test "repay_futures_negative_balance requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      result = PortfolioMargin.repay_futures_negative_balance(%{}, opts)
      assert_pm_success_or_not_configured(result)
    end
  end

  describe "Error parsing verification" do
    test "endpoints return properly parsed errors for common issues", %{api_key: api_key, api_secret: api_secret} do
      # Test with known bad parameters to verify error parsing
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      # Test invalid symbol error
      result =
        PortfolioMargin.new_um_order(
          %{
            symbol: "NONEXISTENT",
            side: "BUY",
            type: "LIMIT",
            quantity: "1",
            price: "100"
          },
          opts
        )

      # Either PM credentials work (and we get an error about the symbol)
      # or PM credentials aren't configured
      case result do
        {:error, %{"code" => code}} when code not in [-2014, -2015, -11_001] ->
          # Got an actual API error (like invalid symbol) - good!
          :ok

        {:error, %{"code" => code}} when code in [-2014, -2015, -11_001] ->
          # PM credentials not configured - acceptable
          :ok

        {:ok, _} ->
          flunk("Expected error with nonexistent symbol")

        {:error, other} ->
          flunk("Unexpected error format: #{inspect(other)}")
      end

      # Test missing required parameter
      case PortfolioMargin.new_cm_order(%{symbol: "BTCUSDT"}, opts) do
        {:error, {:missing_params, _}} ->
          :ok

        {:error, %{"code" => code}} when code in [-2014, -2015, -11_001] ->
          # PM credentials not configured - can't test missing params validation
          :ok

        {:error, reason} ->
          flunk("Expected missing_params error, got: #{inspect(reason)}")

        {:ok, _} ->
          flunk("Expected error with missing parameters")
      end
    end
  end
end
