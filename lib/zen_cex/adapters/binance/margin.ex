defmodule ZenCex.Adapters.Binance.Margin do
  @moduledoc """
  Margin trading endpoints for Binance.

  Contains all margin trading operations including:
  - Cross and Isolated margin account management
  - Transfers between spot and margin accounts
  - Borrowing and repayment operations
  - Margin orders (similar to spot but in margin account)
  - Interest rate queries and history
  - Risk management (margin levels, liquidation info)
  - OCO/OTO/OTOCO orders for margin accounts

  These endpoints use the /sapi/v1/margin/ path prefix and share rate limits
  with other sapi endpoints (12,000 requests per minute).
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints, debug: false

  alias ZenCex.Adapters.Binance.EndpointLoader
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RequestHelper

  require EndpointLoader
  require Logger

  # Timeout for complex order operations (OCO, OTO, OTOCO) in milliseconds
  @complex_order_timeout_ms 2_000

  # Load generated endpoints using the shared macro with filtering
  EndpointLoader.load_endpoints("generated_margin_endpoints.ex", fn endpoint ->
    case endpoint.operation do
      # Rename account operations for consistency
      :get_account ->
        %{endpoint | operation: :get_cross_margin_account, response_parser: &Parser.parse_account/1}

      :get_isolated_account ->
        %{endpoint | operation: :get_isolated_margin_account, response_parser: &Parser.parse_account/1}

      # Rename borrow/repay operations
      :place_borrow_repay ->
        %{endpoint | operation: :borrow_or_repay}

      :get_borrow_repay ->
        %{endpoint | operation: :get_borrow_repay_history}

      # Rename interest operations
      :get_interestHistory ->
        %{endpoint | operation: :get_interest_history}

      :get_interestRateHistory ->
        %{endpoint | operation: :get_interest_rate_history}

      # Rename transfer operations
      :get_maxTransferable ->
        %{endpoint | operation: :get_max_transferable}

      :get_maxBorrowable ->
        %{endpoint | operation: :get_max_borrowable}

      # Rename order operations for clarity
      :get_allOrders ->
        %{endpoint | operation: :get_order_history}

      :get_allOrderList ->
        %{endpoint | operation: :get_oco_history}

      :get_myTrades ->
        %{endpoint | operation: :get_trade_history}

      :cancel_openOrders ->
        %{endpoint | operation: :cancel_all_orders}

      # Fix isolated margin account enable/disable
      :place_isolated_account ->
        %{endpoint | operation: :enable_isolated_margin}

      :cancel_isolated_account ->
        %{endpoint | operation: :disable_isolated_margin}

      # Fix listen key operations
      :place_listen_key ->
        %{endpoint | operation: :create_listen_key}

      :update_listen_key ->
        %{endpoint | operation: :keepalive_listen_key}

      :cancel_listen_key ->
        %{endpoint | operation: :close_listen_key}

      # Fix isolated user data stream
      :place_isolated ->
        %{endpoint | operation: :create_isolated_listen_key}

      :update_isolated ->
        %{endpoint | operation: :keepalive_isolated_listen_key}

      :cancel_isolated ->
        %{endpoint | operation: :close_isolated_listen_key}

      # Complex order operations need special settings
      op when op in [:place_order_oco, :place_order_oto, :place_order_otoco] ->
        # Never retry complex orders
        %{endpoint | max_retries: 0, retry_on: [], timeout: @complex_order_timeout_ms}

      # Regular order operations
      op when op in [:place_order] ->
        # Never retry order placement
        %{endpoint | max_retries: 0, retry_on: []}

      op when op in [:cancel_order, :cancel_orderList] ->
        # Allow timeout retry for cancellations
        %{endpoint | max_retries: 1, retry_on: [:timeout]}

      _ ->
        endpoint
    end
  end)

  # Filter out unwanted endpoints after loading
  # Override the @endpoints attribute with filtered version
  @endpoints Enum.reject(@endpoints, fn endpoint ->
               endpoint.operation in [
                 :get_api_key_list,
                 :place_apiKey,
                 :cancel_apiKey,
                 :get_apiKey,
                 :update_apiKey_ip,
                 # This is the misnamed bnbBurn operation
                 :get
               ]
             end)

  # The EndpointRegistry macro automatically generates functions for all endpoints

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the high-level helper with Margin-specific logic
    RequestHelper.execute_request_for_api_type(
      config,
      params,
      opts,
      :margin,
      &determine_margin_operation_type/1
    )
  end

  # Determine operation type for margin endpoints
  defp determine_margin_operation_type(config) do
    cond do
      # Transfer operations need special handling
      String.contains?(config.path, "/transfer") -> :transfer
      # Borrow/repay operations
      String.contains?(config.path, "/borrow") -> :loan
      # Everything else is standard
      true -> :standard
    end
  end
end
