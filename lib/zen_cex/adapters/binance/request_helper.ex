defmodule ZenCex.Adapters.Binance.RequestHelper do
  @moduledoc """
  Shared request execution logic for Binance adapter modules.

  This module extracts common request building and execution patterns
  to avoid code duplication across Common, Spot, and Futures modules.
  """

  alias ZenCex.Core.HTTP
  require Logger

  @doc """
  Executes a request with the given configuration.

  ## Parameters
  - `config` - Endpoint configuration map containing method, path, parsers, etc.
  - `params` - Request parameters (query params for GET, body for POST/PUT/DELETE)
  - `opts` - Additional options like custom timeout
  - `base_url` - The base URL for the API endpoint
  - `exchange` - The exchange atom (:binance)
  - `operation_type` - The operation type for Core.HTTP (:standard, :trading, :health, etc.)

  ## Returns
  - `{:ok, result}` - Parsed successful response
  - `{:error, reason}` - Error from parser or exception

  ## Error Scenarios

  The function handles several error cases:

  1. **HTTP Success (200-299)**: Response is parsed using `config.response_parser`
  2. **HTTP Error (non-2xx)**: Response is parsed using `config.error_mapping`
  3. **Network/Request Exception**: Logged and returned as `{:error, exception}`

  ### Common Error Responses

  - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
  - `{:error, {:insufficient_balance, "Account has insufficient balance"}}` - Not enough funds
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  - `{:error, %Mint.TransportError{}}` - Network connectivity issues
  - `{:error, %Req.Response.AsyncError{}}` - Request timeout
  """
  @spec execute_request(map(), map(), keyword(), String.t(), atom(), atom()) ::
          {:ok, map()} | {:error, term()}
  def execute_request(config, params, opts, base_url, exchange, operation_type) do
    # Build request params based on method
    request_params = build_request_params(config.method, params)

    # Build request using Core.HTTP patterns
    request =
      HTTP.base_request(exchange, operation_type)
      |> Req.merge(
        method: config.method,
        url: base_url <> config.path,
        params: request_params.params,
        json: request_params.json,
        receive_timeout: Keyword.get(opts, :timeout, config.timeout),
        skip_auth: not config.requires_auth,
        retry: false
      )
      |> Req.Request.put_private(:rate_limit_weight, config.weight)
      |> Req.Request.put_private(:endpoint_config, config)
      |> Req.Request.put_private(:endpoint_operation, config.operation)

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

  # Private helper to build request params based on HTTP method
  defp build_request_params(:get, params) do
    %{params: params, json: nil}
  end

  defp build_request_params(_method, params) do
    %{params: nil, json: params}
  end
end
