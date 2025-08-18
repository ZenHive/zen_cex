defmodule ZenCex.Adapters.Binance.Common do
  @moduledoc """
  Common endpoints shared across all Binance API types.

  Contains endpoints that are available on all API types like
  server time, exchange info, etc.
  """

  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Core.HTTP
  require Logger

  @endpoint_config %{
    operation: :get_server_time,
    method: :get,
    path: "/api/v3/time",
    requires_auth: false,
    weight: 1,
    # 2 second timeout
    timeout: 2_000,
    # Public endpoint, only retry on timeout
    retry_on: [:timeout],
    response_parser: &Parser.parse_server_time/1,
    error_mapping: &Parser.parse_error/1
  }

  @doc """
  Get server time from the exchange.
  """
  @spec get_server_time() :: {:ok, map()} | {:error, term()}
  def get_server_time(opts \\ []) do
    config = @endpoint_config
    base_url = ZenCex.Adapters.Binance.Endpoints.base_url()

    # Build request using Core.HTTP patterns
    request =
      HTTP.base_request(:binance, :health)
      |> Req.merge(
        method: config.method,
        url: base_url <> config.path,
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

  @doc """
  Returns the endpoint configuration for the given operation.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(:get_server_time), do: @endpoint_config
  def get_endpoint(_), do: nil

  @doc """
  Returns all endpoints defined in this module.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints, do: [@endpoint_config]
end
