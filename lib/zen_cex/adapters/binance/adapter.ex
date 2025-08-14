defmodule ZenCex.Adapters.Binance.Adapter do
  @moduledoc """
  Binance exchange adapter implementation.

  Provides access to Binance spot and futures markets with:
  - Account information and balances
  - Open positions tracking
  - Order placement and cancellation
  - Market data retrieval

  ## Important Notes
  - Requires API key and secret for authenticated endpoints
  - Supports both spot and futures markets
  - Timestamp must be within 5000ms window
  - Signature must be the last query parameter
  """

  @behaviour ZenCex.Behaviors.Adapter

  alias ZenCex.Core.HTTP

  @impl true
  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"

  @impl true
  def get_positions(params) do
    # For futures positions
    endpoint = "/fapi/v2/positionRisk"

    with {:ok, request} <- build_request(:futures, endpoint, params),
         {:ok, response} <- execute_request(request) do
      parse_positions(response)
    end
  end

  @impl true
  def get_balances(params) do
    # For spot account balances
    endpoint = "/api/v3/account"

    with {:ok, request} <- build_request(:spot, endpoint, params),
         {:ok, response} <- execute_request(request) do
      parse_balances(response)
    end
  end

  @impl true
  def place_order(symbol, side, type, params) do
    endpoint = determine_order_endpoint(params)

    order_params =
      params
      |> Map.put(:symbol, symbol)
      |> Map.put(:side, to_string(side) |> String.upcase())
      |> Map.put(:type, to_string(type) |> String.upcase())

    with {:ok, request} <- build_request(:trading, endpoint, order_params, :post),
         {:ok, response} <- execute_request(request) do
      {:ok, response}
    end
  end

  @impl true
  def cancel_order(order_id, params) do
    market_type = Map.get(params, :market_type, :spot)

    endpoint =
      case market_type do
        :futures -> "/fapi/v1/order"
        _ -> "/api/v3/order"
      end

    cancel_params = Map.put(params, :orderId, order_id)

    with {:ok, request} <- build_request(:trading, endpoint, cancel_params, :delete),
         {:ok, response} <- execute_request(request) do
      {:ok, response}
    end
  end

  # Additional public functions for Binance-specific features

  def get_server_time do
    endpoint = "/api/v3/time"

    with {:ok, request} <- build_public_request(endpoint),
         {:ok, response} <- execute_request(request) do
      {:ok, response["serverTime"]}
    end
  end

  def get_exchange_info(params \\ %{}) do
    endpoint = "/api/v3/exchangeInfo"

    with {:ok, request} <- build_public_request(endpoint, params),
         {:ok, response} <- execute_request(request) do
      {:ok, response}
    end
  end

  def get_ticker_price(symbol) do
    endpoint = "/api/v3/ticker/price"
    params = %{symbol: symbol}

    with {:ok, request} <- build_public_request(endpoint, params),
         {:ok, response} <- execute_request(request) do
      {:ok, response}
    end
  end

  # Private helper functions

  defp build_request(operation_type, endpoint, params, method \\ :get) do
    request =
      HTTP.base_request(:binance, operation_type)
      |> Req.merge(
        method: method,
        url: endpoint,
        params: params
      )

    # Add authentication if needed
    if requires_auth?(endpoint) do
      case apply_auth(request) do
        {:ok, authed_request} -> {:ok, authed_request}
        error -> error
      end
    else
      {:ok, request}
    end
  end

  defp build_public_request(endpoint, params \\ %{}) do
    request =
      HTTP.base_request(:binance, :market)
      |> Req.merge(
        method: :get,
        url: endpoint,
        params: params
      )

    {:ok, request}
  end

  defp apply_auth(request) do
    # Check for API credentials
    api_key = System.get_env("BINANCE_API_KEY")
    api_secret = System.get_env("BINANCE_API_SECRET")

    if api_key && api_secret do
      # Add timestamp
      timestamp = System.system_time(:millisecond)
      params = Map.put(request.params, :timestamp, timestamp)

      # Add recvWindow if not present
      params = Map.put_new(params, :recvWindow, 5000)

      # Generate signature
      query_string = URI.encode_query(params)

      signature =
        :crypto.mac(:hmac, :sha256, api_secret, query_string)
        |> Base.encode16(case: :lower)

      # Signature must be last parameter
      params = Map.put(params, :signature, signature)

      # Add API key header
      headers = [{"X-MBX-APIKEY", api_key}]

      request =
        request
        |> Req.merge(
          params: params,
          headers: headers
        )

      {:ok, request}
    else
      {:error, :missing_credentials}
    end
  end

  defp execute_request(request) do
    # Check rate limits first
    with :ok <- check_rate_limit(request),
         {:ok, response} <- Req.request(request) do
      handle_response(response)
    end
  end

  defp check_rate_limit(_request) do
    # TODO: Delegate to rate limiter when available
    # TODO: For now, just pass through
    :ok
  end

  defp handle_response(%{status: status, body: body}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response(%{status: 429}) do
    {:error, :rate_limited}
  end

  defp handle_response(%{status: status, body: body}) do
    error_msg =
      case body do
        %{"msg" => msg} -> msg
        %{"message" => msg} -> msg
        _ -> "HTTP #{status}"
      end

    {:error, error_msg}
  end

  defp parse_positions(response) when is_list(response) do
    positions =
      response
      |> Enum.filter(fn pos ->
        # Filter out positions with 0 quantity
        case pos do
          %{"positionAmt" => amt} when is_binary(amt) ->
            String.to_float(amt) != 0.0

          %{"positionAmt" => amt} when is_number(amt) ->
            amt != 0

          _ ->
            false
        end
      end)
      |> Enum.map(&format_position/1)

    {:ok, positions}
  end

  defp parse_positions(_), do: {:error, :invalid_response}

  defp parse_balances(%{"balances" => balances}) when is_list(balances) do
    formatted_balances =
      balances
      |> Enum.filter(fn balance ->
        # Filter out zero balances
        free = parse_amount(balance["free"])
        locked = parse_amount(balance["locked"])
        free > 0 || locked > 0
      end)
      |> Enum.map(&format_balance/1)

    {:ok, formatted_balances}
  end

  defp parse_balances(_), do: {:error, :invalid_response}

  defp format_position(position) do
    %{
      symbol: position["symbol"],
      position_amount: parse_amount(position["positionAmt"]),
      entry_price: parse_amount(position["entryPrice"]),
      mark_price: parse_amount(position["markPrice"]),
      unrealized_pnl: parse_amount(position["unRealizedProfit"]),
      margin_type: position["marginType"],
      side: determine_position_side(position)
    }
  end

  defp format_balance(balance) do
    %{
      asset: balance["asset"],
      free: parse_amount(balance["free"]),
      locked: parse_amount(balance["locked"]),
      total: parse_amount(balance["free"]) + parse_amount(balance["locked"])
    }
  end

  defp parse_amount(nil), do: 0.0

  defp parse_amount(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp parse_amount(amount) when is_number(amount), do: amount

  defp determine_position_side(%{"positionAmt" => amt}) do
    amount = parse_amount(amt)

    cond do
      amount > 0 -> :long
      amount < 0 -> :short
      true -> :flat
    end
  end

  defp determine_order_endpoint(params) do
    case Map.get(params, :market_type, :spot) do
      :futures -> "/fapi/v1/order"
      _ -> "/api/v3/order"
    end
  end

  defp requires_auth?(endpoint) do
    public_endpoints = [
      "/api/v3/time",
      "/api/v3/exchangeInfo",
      "/api/v3/ticker/price",
      "/api/v3/ticker/24hr",
      "/api/v3/depth",
      "/api/v3/klines"
    ]

    endpoint not in public_endpoints
  end
end
