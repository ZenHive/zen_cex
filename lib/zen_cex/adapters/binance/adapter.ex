defmodule ZenCex.Adapters.Binance.Adapter do
  @moduledoc """
  Binance exchange adapter implementation.

  Provides a unified interface for interacting with Binance REST API
  including spot trading, futures, and account management.
  """

  @behaviour ZenCex.Behaviors.Adapter

  require Logger

  @impl true
  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"
  def base_url(:futures_prod), do: "https://fapi.binance.com"
  def base_url(:futures_test), do: "https://testnet.binancefuture.com"

  @impl true
  def get_positions(params) do
    # For Binance futures positions
    request = build_request("/fapi/v2/positionRisk", params, :futures_prod)

    case execute_request(request) do
      {:ok, %{status: 200, body: body}} ->
        positions = parse_positions(body)
        {:ok, positions}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_balances(params) do
    request = build_request("/api/v3/account", params, :prod)

    case execute_request(request) do
      {:ok, %{status: 200, body: body}} ->
        balances = parse_balances(body)
        {:ok, balances}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def place_order(symbol, side, type, params) do
    order_params =
      params
      |> Map.put("symbol", symbol)
      |> Map.put("side", to_binance_side(side))
      |> Map.put("type", to_binance_order_type(type))

    request = build_request("/api/v3/order", order_params, :prod, :post)

    case execute_request(request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def cancel_order(order_id, params) do
    cancel_params = Map.put(params, "orderId", order_id)
    request = build_request("/api/v3/order", cancel_params, :prod, :delete)

    case execute_request(request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Public API endpoints (no authentication required)
  def get_server_time do
    request = build_public_request("/api/v3/time", %{}, :prod)

    case execute_request(request) do
      {:ok, %{status: 200, body: %{"serverTime" => time}}} ->
        {:ok, time}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_exchange_info(params \\ %{}) do
    request = build_public_request("/api/v3/exchangeInfo", params, :prod)

    case execute_request(request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_ticker_price(params \\ %{}) do
    request = build_public_request("/api/v3/ticker/price", params, :prod)

    case execute_request(request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp build_request(path, params, env, method \\ :get) do
    base = base_url(env)

    Logger.debug(
      "build_request - path: #{path}, params: #{inspect(params)}, env: #{env}, method: #{method}"
    )

    request = ZenCex.Core.HTTP.base_request(:binance)
    Logger.debug("build_request - base request options: #{inspect(request.options)}")

    # Don't merge params here if we need authentication - let add_auth handle all params
    auth_needed = path not in ["/api/v3/time", "/api/v3/exchangeInfo", "/api/v3/ticker/price"]

    merge_opts =
      if auth_needed do
        # Don't include params here - add_auth will handle them
        [
          base_url: base,
          url: path,
          method: method
        ]
      else
        # For public endpoints, include params directly
        [
          base_url: base,
          url: path,
          params: params,
          method: method
        ]
      end

    request = Req.merge(request, merge_opts)
    Logger.debug("build_request - after merge options: #{inspect(request.options)}")

    result = add_auth_if_needed(request, path, params)
    Logger.debug("build_request - after auth options: #{inspect(result.options)}")

    result
  end

  defp build_public_request(path, params, env) do
    base = base_url(env)

    ZenCex.Core.HTTP.base_request(:binance)
    |> Req.merge(
      base_url: base,
      url: path,
      params: params,
      method: :get
    )
  end

  defp add_auth_if_needed(request, path, params \\ %{}) do
    # Public endpoints don't need authentication
    public_endpoints = ["/api/v3/time", "/api/v3/exchangeInfo", "/api/v3/ticker/price"]

    if path in public_endpoints do
      request
    else
      add_authentication(request, params)
    end
  end

  defp add_authentication(request, original_params \\ %{}) do
    api_key = System.get_env("BINANCE_API_KEY")
    api_secret = System.get_env("BINANCE_API_SECRET")

    if api_key && api_secret do
      timestamp = System.system_time(:millisecond)

      # Use the original params passed from build_request
      Logger.debug("add_authentication - original_params: #{inspect(original_params)}")

      params =
        original_params
        |> Map.put("timestamp", timestamp)
        |> Map.put("recvWindow", 5000)

      query_string = URI.encode_query(params)
      signature = generate_signature(query_string, api_secret)

      params = Map.put(params, "signature", signature)
      Logger.debug("add_authentication - final params: #{inspect(params)}")

      # Headers must be a list of tuples for Req
      headers = [{"X-MBX-APIKEY", api_key}]
      Logger.debug("add_authentication - headers: #{inspect(headers)}")

      Logger.debug(
        "add_authentication - about to merge with params: #{inspect(params)} and headers: #{inspect(headers)}"
      )

      result = Req.merge(request, params: params, headers: headers)
      Logger.debug("add_authentication - result options after merge: #{inspect(result.options)}")

      result
    else
      Logger.warning("Binance API credentials not configured")
      request
    end
  end

  defp generate_signature(data, secret) do
    :crypto.mac(:hmac, :sha256, secret, data)
    |> Base.encode16(case: :lower)
  end

  defp execute_request(request) do
    Req.request(request)
  end

  defp parse_positions(positions) when is_list(positions) do
    Enum.map(positions, fn pos ->
      %{
        symbol: pos["symbol"],
        position_amt: parse_decimal(pos["positionAmt"]),
        entry_price: parse_decimal(pos["entryPrice"]),
        mark_price: parse_decimal(pos["markPrice"]),
        unrealized_pnl: parse_decimal(pos["unRealizedProfit"]),
        position_side: pos["positionSide"]
      }
    end)
  end

  defp parse_positions(_), do: []

  defp parse_balances(%{"balances" => balances}) when is_list(balances) do
    balances
    |> Enum.filter(fn b ->
      free = parse_decimal(b["free"])
      locked = parse_decimal(b["locked"])
      Decimal.gt?(free, Decimal.new(0)) or Decimal.gt?(locked, Decimal.new(0))
    end)
    |> Enum.map(fn balance ->
      %{
        asset: balance["asset"],
        free: parse_decimal(balance["free"]),
        locked: parse_decimal(balance["locked"])
      }
    end)
  end

  defp parse_balances(_), do: []

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(""), do: Decimal.new(0)

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _remainder} -> decimal
      :error -> Decimal.new(0)
    end
  end

  defp parse_decimal(value) when is_number(value), do: Decimal.new(value)
  defp parse_decimal(_), do: Decimal.new(0)

  defp to_binance_side(:buy), do: "BUY"
  defp to_binance_side(:sell), do: "SELL"
  defp to_binance_side(side) when is_binary(side), do: String.upcase(side)

  defp to_binance_order_type(:market), do: "MARKET"
  defp to_binance_order_type(:limit), do: "LIMIT"
  defp to_binance_order_type(:stop_loss), do: "STOP_LOSS"
  defp to_binance_order_type(:stop_loss_limit), do: "STOP_LOSS_LIMIT"
  defp to_binance_order_type(:take_profit), do: "TAKE_PROFIT"
  defp to_binance_order_type(:take_profit_limit), do: "TAKE_PROFIT_LIMIT"
  defp to_binance_order_type(type) when is_binary(type), do: String.upcase(type)
end
