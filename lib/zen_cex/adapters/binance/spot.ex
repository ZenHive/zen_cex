defmodule ZenCex.Adapters.Binance.Spot do
  @moduledoc """
  Spot trading endpoints for Binance.

  Contains all spot trading operations including:
  - Order management (place, cancel, query)
  - Account information (balances)
  - OCO orders
  - Batch operations
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints, debug: false

  alias ZenCex.Adapters.Binance.EndpointLoader
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RequestHelper

  require EndpointLoader
  require Logger

  # Timeout for complex order operations (OCO, OTO, OTOCO) in milliseconds
  @complex_order_timeout_ms 2_000

  # Load generated endpoints using the shared macro
  EndpointLoader.load_endpoints("generated_endpoints.ex", fn endpoint ->
    case endpoint.operation do
      # Fix balances operation name and parser
      :get_account ->
        %{endpoint | operation: :get_balances, response_parser: &Parser.parse_balances/1}

      # Fix account commission to use fees parser
      :"get_account/commission" ->
        %{endpoint | operation: :get_commission_rates, response_parser: &Parser.parse_fees/1}

      # Fix some operation names to be more intuitive
      :get_allOrders ->
        %{endpoint | operation: :get_order_history}

      :get_allOrderList ->
        %{endpoint | operation: :get_oco_history}

      :get_myTrades ->
        %{endpoint | operation: :get_trade_history}

      :delete_openOrders ->
        %{endpoint | operation: :cancel_all_orders}

      # Fix timeout for OCO operations (they're complex)
      op when op in [:"place_orderList/oco", :"place_orderList/oto", :"place_orderList/otoco"] ->
        # Never retry complex orders
        %{endpoint | timeout: @complex_order_timeout_ms, max_retries: 0, retry_on: []}

      _ ->
        endpoint
    end
  end)

  # The macro generates get_balances/1, place_order/1, cancel_order/1, get_order/1
  # along with their /2 variants and proper documentation

  @doc """
  Complex operation: Place One-Cancels-Other order.
  Hand-written because it requires special parameter handling.
  """
  @spec place_oco_order(map()) :: {:ok, map()} | {:error, term()}
  def place_oco_order(_params) do
    # TODO: Implement OCO order placement
    # This is a complex operation that places two orders where one cancels the other
    {:error, :not_implemented}
  end

  @doc """
  Complex operation: Batch cancel multiple orders.
  Hand-written because it requires special batch handling.
  """
  @spec batch_cancel_orders(map()) :: {:ok, list(map())} | {:error, term()}
  def batch_cancel_orders(_params) do
    # TODO: Implement batch cancellation
    # This cancels multiple orders in a single API call
    {:error, :not_implemented}
  end

  # The EndpointRegistry macro automatically generates:
  # - get_endpoint/1
  # - all_endpoints/0
  # - get_weight/1
  # - Individual endpoint functions with proper specs and docs

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  # IMPORTANT: This must return {:ok, unparsed_body} or {:error, reason}
  # The EndpointRegistry macro will handle parsing the response
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the new high-level helper with Spot-specific logic
    RequestHelper.execute_request_for_api_type(
      config,
      params,
      opts,
      :spot,
      &RequestHelper.determine_spot_operation_type/1
    )
  end
end
