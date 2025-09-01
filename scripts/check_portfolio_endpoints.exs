#!/usr/bin/env elixir

# Script to check which Binance Portfolio Margin endpoints are available on testnet
# Usage: elixir scripts/check_portfolio_endpoints.exs
#
# This script tests all portfolio margin endpoints against Binance testnet to identify
# which endpoints are supported and which return errors.

Mix.install([
  {:req, "~> 0.4.0"},
  {:jason, "~> 1.4"}
])

defmodule PortfolioEndpointChecker do
  @moduledoc """
  Checks availability of Binance Portfolio Margin endpoints on testnet.

  Tests each endpoint with minimal parameters to see if it returns:
  - 200: Available and working
  - 404: Not available on testnet
  - 400: Available but requires different parameters
  - 401: Available but requires authentication
  - Other: Unexpected behavior
  """

  # Testnet base URL - CRITICAL: Only use testnet for safety
  @base_url "https://testnet.binance.vision"
  @papi_prefix "/papi/v1"

  # Test credentials - these should be testnet credentials or empty for public endpoints
  @api_key System.get_env("BINANCE_TESTNET_API_KEY") || ""
  @api_secret System.get_env("BINANCE_TESTNET_API_SECRET") || ""

  # All portfolio margin endpoints from the generated file
  @endpoints [
    # Account endpoints
    %{operation: :account_information, method: :get, path: "/papi/v1/account", requires_auth: true},
    %{operation: :account_balance, method: :get, path: "/papi/v1/balance", requires_auth: true},

    # CM Futures endpoints
    %{operation: :get_cm_account_detail, method: :get, path: "/papi/v1/cm/account", requires_auth: true},
    %{operation: :get_user_commission_rate_for_cm, method: :get, path: "/papi/v1/cm/commissionRate", requires_auth: true},
    %{operation: :get_cm_income_history, method: :get, path: "/papi/v1/cm/income", requires_auth: true},
    %{operation: :change_cm_initial_leverage, method: :post, path: "/papi/v1/cm/leverage", requires_auth: true},
    %{operation: :cm_notional_and_leverage_brackets, method: :get, path: "/papi/v1/cm/leverageBracket", requires_auth: true},
    %{operation: :query_cm_position_information, method: :get, path: "/papi/v1/cm/positionRisk", requires_auth: true},
    %{operation: :change_cm_position_mode, method: :post, path: "/papi/v1/cm/positionSide/dual", requires_auth: true},
    %{operation: :get_cm_current_position_mode, method: :get, path: "/papi/v1/cm/positionSide/dual", requires_auth: true},

    # UM Futures endpoints
    %{operation: :get_um_account_detail, method: :get, path: "/papi/v1/um/account", requires_auth: true},
    %{operation: :um_futures_account_configuration, method: :get, path: "/papi/v1/um/accountConfig", requires_auth: true},
    %{operation: :portfolio_margin_um_trading_quantitative_rules_indicators, method: :get, path: "/papi/v1/um/apiTradingStatus", requires_auth: true},
    %{operation: :get_user_commission_rate_for_um, method: :get, path: "/papi/v1/um/commissionRate", requires_auth: true},
    %{operation: :get_um_income_history, method: :get, path: "/papi/v1/um/income", requires_auth: true},
    %{operation: :change_um_initial_leverage, method: :post, path: "/papi/v1/um/leverage", requires_auth: true},
    %{operation: :um_notional_and_leverage_brackets, method: :get, path: "/papi/v1/um/leverageBracket", requires_auth: true},
    %{operation: :query_um_position_information, method: :get, path: "/papi/v1/um/positionRisk", requires_auth: true},
    %{operation: :change_um_position_mode, method: :post, path: "/papi/v1/um/positionSide/dual", requires_auth: true},
    %{operation: :get_um_current_position_mode, method: :get, path: "/papi/v1/um/positionSide/dual", requires_auth: true},
    %{operation: :get_um_account_detail_v2, method: :get, path: "/papi/v2/um/account", requires_auth: true},

    # Margin endpoints
    %{operation: :get_margin_borrow_loan_interest_history, method: :get, path: "/papi/v1/margin/marginInterestHistory", requires_auth: true},
    %{operation: :query_margin_loan_record, method: :get, path: "/papi/v1/margin/marginLoan", requires_auth: true},
    %{operation: :margin_max_borrow, method: :get, path: "/papi/v1/margin/maxBorrowable", requires_auth: true},
    %{operation: :query_margin_max_withdraw, method: :get, path: "/papi/v1/margin/maxWithdraw", requires_auth: true},
    %{operation: :query_margin_repay_record, method: :get, path: "/papi/v1/margin/repayLoan", requires_auth: true},

    # Portfolio-specific endpoints
    %{operation: :query_portfolio_margin_negative_balance_interest_history, method: :get, path: "/papi/v1/portfolio/interest-history", requires_auth: true},
    %{operation: :query_user_negative_balance_auto_exchange_record, method: :get, path: "/papi/v1/portfolio/negative-balance-exchange-record", requires_auth: true},
    %{operation: :repay_futures_negative_balance, method: :post, path: "/papi/v1/repay-futures-negative-balance", requires_auth: true},

    # Trading endpoints (more likely to be disabled on testnet)
    %{operation: :new_um_order, method: :post, path: "/papi/v1/um/order", requires_auth: true},
    %{operation: :query_um_order, method: :get, path: "/papi/v1/um/order", requires_auth: true},
    %{operation: :cancel_um_order, method: :delete, path: "/papi/v1/um/order", requires_auth: true},
    %{operation: :new_cm_order, method: :post, path: "/papi/v1/cm/order", requires_auth: true},
    %{operation: :query_cm_order, method: :get, path: "/papi/v1/cm/order", requires_auth: true},
    %{operation: :cancel_cm_order, method: :delete, path: "/papi/v1/cm/order", requires_auth: true},
    %{operation: :new_margin_order, method: :post, path: "/papi/v1/margin/order", requires_auth: true},
    %{operation: :query_margin_account_order, method: :get, path: "/papi/v1/margin/order", requires_auth: true},
    %{operation: :cancel_margin_account_order, method: :delete, path: "/papi/v1/margin/order", requires_auth: true},

    # Borrow/Repay endpoints
    %{operation: :margin_account_borrow, method: :post, path: "/papi/v1/marginLoan", requires_auth: false},
    %{operation: :margin_account_repay, method: :post, path: "/papi/v1/repayLoan", requires_auth: false}
  ]

  def run do
    IO.puts("🔍 Checking Binance Portfolio Margin endpoints on testnet...")
    IO.puts("📍 Base URL: #{@base_url}")
    IO.puts("🔑 API Key present: #{if @api_key != "", do: "Yes", else: "No"}")
    IO.puts("")

    if @api_key == "" do
      IO.puts("⚠️  Warning: No BINANCE_TESTNET_API_KEY found. Only public endpoints will be tested properly.")
      IO.puts("   Set environment variables for full testing:")
      IO.puts("   export BINANCE_TESTNET_API_KEY=your_testnet_key")
      IO.puts("   export BINANCE_TESTNET_API_SECRET=your_testnet_secret")
      IO.puts("")
    end

    results = Enum.map(@endpoints, &test_endpoint/1)

    # Categorize results
    available = Enum.filter(results, fn {_, status, _} -> status == :available end)
    unavailable = Enum.filter(results, fn {_, status, _} -> status == :unavailable end)
    auth_required = Enum.filter(results, fn {_, status, _} -> status == :auth_required end)
    param_error = Enum.filter(results, fn {_, status, _} -> status == :param_error end)
    unknown = Enum.filter(results, fn {_, status, _} -> status not in [:available, :unavailable, :auth_required, :param_error] end)

    print_summary(available, unavailable, auth_required, param_error, unknown)

    # Return the categorized lists for programmatic use
    %{
      available: Enum.map(available, fn {op, _, _} -> op end),
      unavailable: Enum.map(unavailable, fn {op, _, _} -> op end),
      auth_required: Enum.map(auth_required, fn {op, _, _} -> op end),
      param_error: Enum.map(param_error, fn {op, _, _} -> op end),
      unknown: Enum.map(unknown, fn {op, _, _} -> op end)
    }
  end

  defp test_endpoint(endpoint) do
    %{operation: operation, method: method, path: path, requires_auth: requires_auth} = endpoint

    url = @base_url <> path

    # Add minimal test parameters based on endpoint type
    params = get_test_params(operation, path)

    # Add authentication if available and required
    headers = if requires_auth and @api_key != "" do
      signature_params = add_signature(params)
      query_string = URI.encode_query(signature_params)

      [
        {"X-MBX-APIKEY", @api_key},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]
    else
      [{"Content-Type", "application/x-www-form-urlencoded"}]
    end

    # Make request
    try do
      response = case method do
        :get ->
          query_url = if params != %{}, do: url <> "?" <> URI.encode_query(params), else: url
          Req.get!(query_url, headers: headers, receive_timeout: 10_000)
        :post ->
          body = if requires_auth and @api_key != "" do
            add_signature(params) |> URI.encode_query()
          else
            URI.encode_query(params)
          end
          Req.post!(url, body: body, headers: headers, receive_timeout: 10_000)
        :delete ->
          query_url = if params != %{}, do: url <> "?" <> URI.encode_query(params), else: url
          Req.delete!(query_url, headers: headers, receive_timeout: 10_000)
        :put ->
          body = if requires_auth and @api_key != "" do
            add_signature(params) |> URI.encode_query()
          else
            URI.encode_query(params)
          end
          Req.put!(url, body: body, headers: headers, receive_timeout: 10_000)
      end

      status = categorize_response(response, requires_auth)
      message = get_response_message(response)

      print_result(operation, method, path, status, message)

      {operation, status, message}

    catch
      error ->
        print_result(operation, method, path, :error, "Request failed: #{inspect(error)}")
        {operation, :error, "Request failed"}
    end
  end

  defp get_test_params(operation, path) do
    base_params = %{
      "timestamp" => System.system_time(:millisecond),
      "recvWindow" => 5000
    }

    # Add specific test parameters based on endpoint type
    case operation do
      # Order-related endpoints need symbol and basic order params
      op when op in [:new_um_order, :new_cm_order, :new_margin_order] ->
        Map.merge(base_params, %{
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "type" => "LIMIT",
          "quantity" => "0.001",
          "price" => "30000",
          "timeInForce" => "GTC"
        })

      # Query order endpoints might need orderId
      op when op in [:query_um_order, :query_cm_order, :query_margin_account_order] ->
        Map.merge(base_params, %{"symbol" => "BTCUSDT"})

      # Cancel order endpoints need orderId
      op when op in [:cancel_um_order, :cancel_cm_order, :cancel_margin_account_order] ->
        Map.merge(base_params, %{"symbol" => "BTCUSDT", "orderId" => "123456"})

      # Leverage endpoints need symbol
      op when op in [:change_um_initial_leverage, :change_cm_initial_leverage] ->
        Map.merge(base_params, %{"symbol" => "BTCUSDT", "leverage" => "1"})

      # Commission rate endpoints might need symbol
      op when op in [:get_user_commission_rate_for_um, :get_user_commission_rate_for_cm] ->
        Map.merge(base_params, %{"symbol" => "BTCUSDT"})

      # Borrow/repay endpoints need asset and amount
      op when op in [:margin_account_borrow, :margin_account_repay] ->
        Map.merge(base_params, %{"asset" => "BTC", "amount" => "0.001"})

      # Max borrow/withdraw need asset
      op when op in [:margin_max_borrow, :query_margin_max_withdraw] ->
        Map.merge(base_params, %{"asset" => "BTC"})

      # Most other endpoints just need basic auth params
      _ ->
        base_params
    end
  end

  defp add_signature(params) do
    if @api_secret != "" do
      query_string = URI.encode_query(params)
      signature = :crypto.mac(:hmac, :sha256, @api_secret, query_string) |> Base.encode16(case: :lower)
      Map.put(params, "signature", signature)
    else
      params
    end
  end

  defp categorize_response(response, requires_auth) do
    case response.status do
      200 -> :available
      404 -> :unavailable
      400 -> :param_error
      401 -> if requires_auth, do: :auth_required, else: :error
      403 -> :auth_required
      _ -> :unknown
    end
  end

  defp get_response_message(response) do
    case response.body do
      body when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"msg" => msg}} -> msg
          {:ok, %{"code" => code, "msg" => msg}} -> "#{code}: #{msg}"
          {:ok, data} when is_map(data) -> "Success (#{map_size(data)} fields)"
          {:ok, data} when is_list(data) -> "Success (#{length(data)} items)"
          _ -> "HTTP #{response.status}"
        end
      _ ->
        "HTTP #{response.status}"
    end
  end

  defp print_result(operation, method, path, status, message) do
    status_icon = case status do
      :available -> "✅"
      :unavailable -> "❌"
      :auth_required -> "🔐"
      :param_error -> "⚠️"
      :error -> "💥"
      _ -> "❓"
    end

    method_str = method |> to_string() |> String.upcase()
    operation_str = operation |> to_string() |> String.replace("_", " ") |> String.upcase()

    IO.puts("#{status_icon} #{method_str} #{path}")
    IO.puts("   #{operation_str}: #{message}")
    IO.puts("")
  end

  defp print_summary(available, unavailable, auth_required, param_error, unknown) do
    total = length(@endpoints)

    IO.puts("📊 SUMMARY")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Total endpoints tested: #{total}")
    IO.puts("")

    if length(available) > 0 do
      IO.puts("✅ AVAILABLE (#{length(available)}):")
      Enum.each(available, fn {operation, _, message} ->
        IO.puts("   • #{operation} - #{message}")
      end)
      IO.puts("")
    end

    if length(param_error) > 0 do
      IO.puts("⚠️  AVAILABLE BUT NEED DIFFERENT PARAMS (#{length(param_error)}):")
      Enum.each(param_error, fn {operation, _, message} ->
        IO.puts("   • #{operation} - #{message}")
      end)
      IO.puts("")
    end

    if length(auth_required) > 0 do
      IO.puts("🔐 REQUIRE AUTHENTICATION (#{length(auth_required)}):")
      Enum.each(auth_required, fn {operation, _, message} ->
        IO.puts("   • #{operation} - #{message}")
      end)
      IO.puts("")
    end

    if length(unavailable) > 0 do
      IO.puts("❌ NOT AVAILABLE ON TESTNET (#{length(unavailable)}):")
      Enum.each(unavailable, fn {operation, _, message} ->
        IO.puts("   • #{operation} - #{message}")
      end)
      IO.puts("")
    end

    if length(unknown) > 0 do
      IO.puts("❓ UNKNOWN STATUS (#{length(unknown)}):")
      Enum.each(unknown, fn {operation, _, message} ->
        IO.puts("   • #{operation} - #{message}")
      end)
      IO.puts("")
    end

    IO.puts("📋 RECOMMENDATIONS:")
    if length(unavailable) > 0 do
      IO.puts("• Remove or disable #{length(unavailable)} unavailable endpoints in tests")
    end
    if length(param_error) > 0 do
      IO.puts("• Fix parameters for #{length(param_error)} endpoints that need different params")
    end
    if length(auth_required) > 0 and (@api_key == "" or @api_secret == "") do
      IO.puts("• Set testnet credentials to properly test #{length(auth_required)} authenticated endpoints")
    end
    IO.puts("• Focus integration tests on the #{length(available) + length(param_error)} working endpoints")
    IO.puts("")

    IO.puts("🎯 NEXT STEPS:")
    IO.puts("1. Update test files to exclude unavailable endpoints")
    IO.puts("2. Fix parameter issues for endpoints that need different params")
    IO.puts("3. Create separate test categories for available vs unavailable endpoints")
    IO.puts("4. Document which endpoints work on testnet vs production only")
  end
end

# Run the checker
PortfolioEndpointChecker.run()