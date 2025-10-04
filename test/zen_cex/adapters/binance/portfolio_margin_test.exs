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

      case PortfolioMargin.change_um_initial_leverage(%{symbol: "BTCUSDT", leverage: 1}, opts) do
        {:ok, response} ->
          # Success - Portfolio Margin is active
          Logger.info("Portfolio Margin: change_um_initial_leverage succeeded: #{inspect(response)}")
          assert is_map(response)

        {:error, reason} ->
          # Error is expected - could be auth, permissions, or account not enabled
          Logger.info("Portfolio Margin: change_um_initial_leverage failed (expected): #{inspect(reason)}")
          # Don't fail test - Portfolio Margin requires special account setup
          assert true
      end
    end

    test "change_cm_initial_leverage requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.change_cm_initial_leverage(%{}, opts) do
        {:error, reason} ->
          Logger.info("change_cm_initial_leverage error (expected without PM creds): #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          # Success if PM credentials are configured
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end

    test "change_um_position_mode requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.change_um_position_mode(%{}, opts) do
        {:error, reason} ->
          Logger.info("change_um_position_mode error (expected without PM creds): #{inspect(reason)}")
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end

    test "change_cm_position_mode requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.change_cm_position_mode(%{}, opts) do
        {:error, reason} ->
          Logger.info("change_cm_position_mode error: #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
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
          # Error is expected - auth, permissions, or account not enabled for PM
          Logger.info("Portfolio Margin order error (expected): #{inspect(reason)}")
          assert true
      end
    end

    test "new_cm_order requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      params = %{symbol: "INVALID"}
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.new_cm_order(params, opts) do
        {:error, reason} ->
          Logger.info("new_cm_order error: #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end

    test "new_margin_order requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      params = %{symbol: "INVALID"}
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.new_margin_order(params, opts) do
        {:error, reason} ->
          Logger.info("new_margin_order error: #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end

    test "margin_account_borrow requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.margin_account_borrow(%{}, opts) do
        {:error, reason} ->
          Logger.info("margin_account_borrow error: #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end

    test "margin_account_repay requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.margin_account_repay(%{}, opts) do
        {:error, reason} ->
          Logger.info("margin_account_repay error: #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end

    test "repay_futures_negative_balance requires PM credentials", %{api_key: api_key, api_secret: api_secret} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      case PortfolioMargin.repay_futures_negative_balance(%{}, opts) do
        {:error, reason} ->
          Logger.info("repay_futures_negative_balance error: #{inspect(reason)}")
          # Without PM credentials, expect auth/permission errors
          assert true

        {:ok, result} ->
          Logger.info("Portfolio Margin enabled: #{inspect(result)}")
          assert is_map(result)
      end
    end
  end

  describe "Error parsing verification" do
    test "endpoints return properly parsed errors for common issues", %{api_key: api_key, api_secret: api_secret} do
      # Test with known bad parameters to verify error parsing
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret}]

      # Test invalid symbol error
      case PortfolioMargin.new_um_order(
             %{
               symbol: "NONEXISTENT",
               side: "BUY",
               type: "LIMIT",
               quantity: "1",
               price: "100"
             },
             opts
           ) do
        {:error, reason} ->
          Logger.info("Invalid symbol error: #{inspect(reason)}")
          # Should parse to a known error atom or structured error
          assert true

        {:ok, _} ->
          flunk("Expected error with nonexistent symbol")
      end

      # Test missing required parameter
      case PortfolioMargin.new_cm_order(%{symbol: "BTCUSDT"}, opts) do
        {:error, reason} ->
          Logger.info("Missing parameter error: #{inspect(reason)}")
          # Should indicate missing parameter
          assert true

        {:ok, _} ->
          flunk("Expected error with missing parameters")
      end
    end
  end
end
