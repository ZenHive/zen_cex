defmodule ZenCex.Adapters.Binance.Futures do
  @moduledoc """
  Futures trading endpoints for Binance.

  Contains all futures trading operations including:
  - Position management
  - Futures order operations
  - Margin and leverage controls
  """

  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Core.HTTP
  require Logger

  @endpoint_config %{
    operation: :get_positions,
    method: :get,
    path: "/fapi/v2/positionRisk",
    # Uses futures API
    api_type: :futures,
    requires_auth: true,
    weight: 5,
    # 5 second timeout for position query
    timeout: 5_000,
    max_retries: 2,
    retry_on: [:rate_limited, :timeout],
    response_parser: &Parser.parse_positions/1,
    error_mapping: &Parser.parse_error/1
  }

  @doc """
  Get futures positions.
  """
  @spec get_positions(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_positions(params \\ %{}, opts \\ []) do
    config = @endpoint_config

    base_url =
      ZenCex.Adapters.Binance.Endpoints.base_url(
        ZenCex.Adapters.Binance.Endpoints.current_env(),
        :futures
      )

    # Build request using Core.HTTP patterns
    request =
      HTTP.base_request(:binance, :standard)
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
  def get_endpoint(:get_positions), do: @endpoint_config
  def get_endpoint(_), do: nil

  @doc """
  Returns all endpoints defined in this module.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints, do: [@endpoint_config]
end
