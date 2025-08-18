defmodule ZenCex.Adapters.Binance.Spot do
  @moduledoc """
  Spot trading endpoints for Binance.

  Contains all spot trading operations including:
  - Order management (place, cancel, query)
  - Account information (balances)
  - OCO orders
  - Batch operations
  """

  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Core.HTTP
  require Logger

  @endpoints_config %{
    get_balances: %{
      operation: :get_balances,
      method: :get,
      path: "/api/v3/account",
      requires_auth: true,
      weight: 10,
      # 5 second timeout for account query
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:rate_limited, :timeout],
      response_parser: &Parser.parse_balances/1,
      error_mapping: &Parser.parse_error/1
    },
    place_order: %{
      operation: :place_order,
      method: :post,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      # 2 second timeout for trading
      timeout: 2_000,
      # CRITICAL: No retries for order placement
      max_retries: 0,
      # Never retry order placement
      retry_on: [],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    },
    cancel_order: %{
      operation: :cancel_order,
      method: :delete,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      # 2 second timeout for cancellation
      timeout: 2_000,
      # Limited retries for cancellation
      max_retries: 1,
      # Only retry on timeout, not rate limit
      retry_on: [:timeout],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    },
    get_order: %{
      operation: :get_order,
      method: :get,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 2,
      # 5 second timeout for query
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    }
  }

  @doc """
  Get account balances.
  """
  @spec get_balances(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_balances(params \\ %{}, opts \\ []) do
    execute_request(:get_balances, params, opts)
  end

  @doc """
  Place a new order.
  """
  @spec place_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_order(params \\ %{}, opts \\ []) do
    execute_request(:place_order, params, opts)
  end

  @doc """
  Cancel an existing order.
  """
  @spec cancel_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def cancel_order(params \\ %{}, opts \\ []) do
    execute_request(:cancel_order, params, opts)
  end

  @doc """
  Get order details.
  """
  @spec get_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_order(params \\ %{}, opts \\ []) do
    execute_request(:get_order, params, opts)
  end

  @doc """
  Complex operation: Place One-Cancels-Other order.
  Hand-written because it requires special parameter handling.
  """
  def place_oco_order(_params) do
    # TODO: Implement OCO order placement
    # This is a complex operation that places two orders where one cancels the other
    {:error, :not_implemented}
  end

  @doc """
  Complex operation: Batch cancel multiple orders.
  Hand-written because it requires special batch handling.
  """
  def batch_cancel_orders(_params) do
    # TODO: Implement batch cancellation
    # This cancels multiple orders in a single API call
    {:error, :not_implemented}
  end

  @doc """
  Returns the endpoint configuration for the given operation.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(operation) do
    Map.get(@endpoints_config, operation)
  end

  @doc """
  Returns all endpoints defined in this module.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints do
    Map.values(@endpoints_config)
  end

  # Private helper to execute requests
  defp execute_request(operation, params, opts) do
    config = Map.get(@endpoints_config, operation)

    base_url =
      ZenCex.Adapters.Binance.Endpoints.base_url(
        ZenCex.Adapters.Binance.Endpoints.current_env(),
        :spot
      )

    # Determine operation type for Core.HTTP
    operation_type =
      cond do
        operation in [:place_order, :cancel_order] -> :trading
        operation == :get_order -> :standard
        true -> :standard
      end

    # Build request using Core.HTTP patterns
    request =
      HTTP.base_request(:binance, operation_type)
      |> Req.merge(
        method: config.method,
        url: base_url <> config.path,
        params: if(config.method == :get, do: params, else: nil),
        json: if(config.method != :get, do: params, else: nil),
        receive_timeout: Keyword.get(opts, :timeout, config.timeout),
        skip_auth: not config.requires_auth,
        retry: false
      )
      |> Req.Request.put_private(:rate_limit_weight, config.weight)
      |> Req.Request.put_private(:endpoint_config, config)
      |> Req.Request.put_private(:endpoint_operation, operation)

    # Execute request and handle response
    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        config.response_parser.(body)

      {:ok, %Req.Response{body: body}} ->
        config.error_mapping.(body)

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, exception}
    end
  end
end
