defmodule ZenCex.Adapters.Binance.UsdmFutures do
  @moduledoc """
  USD-M Futures (USDT-margined) trading endpoints for Binance.

  Contains all USD-M futures trading operations including:
  - Position management (get positions, position risk)
  - Order operations (place, cancel, modify, query)
  - Account information (balances, commission rates)
  - Margin and leverage controls
  - Income and trade history

  These endpoints use the /fapi/ path prefix and have different rate limits
  from spot trading (2,400 requests per minute).
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.EndpointLoader
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RequestHelper

  require EndpointLoader
  require Logger

  # Timeout for order operations in milliseconds
  @order_timeout_ms 2_000

  # Load generated endpoints using the shared macro
  EndpointLoader.load_endpoints("generated_usdm_endpoints.ex", fn endpoint ->
    case endpoint.operation do
      # Rename some operations for consistency
      :futures_account_balance_v2 ->
        %{endpoint | operation: :get_balances_v2}

      :futures_account_balance_v3 ->
        %{endpoint | operation: :get_balances}

      :position_information_v2 ->
        %{endpoint | operation: :get_positions_v2}

      # Ensure critical operations have proper settings
      op when op in [:place_order, :modify_order, :place_multiple_orders] ->
        # Never retry order operations
        %{endpoint | max_retries: 0, retry_on: [], timeout: @order_timeout_ms}

      op when op in [:cancel_order, :cancel_all_orders, :cancel_multiple_orders] ->
        # Allow timeout retry for cancellations
        %{endpoint | max_retries: 1, retry_on: [:timeout], timeout: @order_timeout_ms}

      _ ->
        endpoint
    end
  end)

  # The EndpointRegistry macro automatically generates functions for all endpoints:
  # - get_positions/1, place_order/1, cancel_order/1, etc.
  # - get_endpoint/1 for runtime lookup
  # - all_endpoints/0 for discovery
  # - get_weight/1 for rate limit calculation

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the new high-level helper with simple operation type logic
    RequestHelper.execute_request_for_api_type(
      config,
      params,
      opts,
      :usdm_futures,
      fn _ -> :standard end
    )
  end
end
