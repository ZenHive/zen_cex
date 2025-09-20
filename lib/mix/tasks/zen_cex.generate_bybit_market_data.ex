defmodule Mix.Tasks.ZenCex.GenerateBybitMarketData do
  @shortdoc "Generate Bybit v5 market data endpoint definitions from Postman collection"
  @moduledoc """
  Generates Bybit v5 market data endpoint definitions from the official Postman collection.

  ## Usage

      mix zen_cex.generate_bybit_market_data

  ## What it does

  1. Downloads the Bybit v5 Postman collection from GitHub
  2. Filters for market data endpoints only
  3. Generates endpoint definitions in the Bybit adapter format
  4. Writes to `lib/zen_cex/adapters/bybit/generated_market_data_endpoints.ex`

  ## Endpoints included

  - Klines/Candlesticks (OHLCV data)
  - Order book depth
  - Tickers (24hr stats, price)
  - Recent trades
  - Open interest
  - Funding rate
  - Mark price
  - Instruments info
  - Risk limit
  - Delivery price (for options)

  All market data endpoints are public and don't require authentication.
  """

  use Mix.Task

  # Default timeout for market data endpoints (3 seconds - typically faster than trading)
  @default_public_timeout_ms 3_000

  # Conservative retry count for public market data endpoints
  @default_max_retries_public 3

  # Default rate limit weight for market data endpoints (uniform weight)
  @default_rate_limit_weight 1

  # Postman collection URL
  @postman_url "https://raw.githubusercontent.com/bybit-exchange/QuickStartWithPostman/refs/heads/main/V5APIs/Open%20API%20V5.postman_collection.json"

  # Market data endpoint patterns to include (as strings)
  @market_data_pattern_strings [
    "/v5/market/kline",
    "/v5/market/orderbook",
    "/v5/market/tickers",
    "/v5/market/recent-trade",
    "/v5/market/open-interest",
    "/v5/market/funding/history",
    "/v5/market/mark-price-kline",
    "/v5/market/index-price-kline",
    "/v5/market/premium-index-price-kline",
    "/v5/market/instruments-info",
    "/v5/market/risk-limit",
    "/v5/market/delivery-price",
    "/v5/market/historical-volatility",
    "/v5/market/insurance"
  ]

  defp market_data_patterns do
    Enum.map(@market_data_pattern_strings, &Regex.compile!/1)
  end

  @doc """
  Runs the Bybit market data endpoint generation task.
  """
  @spec run([String.t()]) :: :ok
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Downloading Bybit v5 Postman collection...")
    collection = fetch_postman_collection()

    Mix.shell().info("Parsing and filtering market data endpoints...")
    endpoints = parse_and_filter_endpoints(collection)

    Mix.shell().info("Found #{length(endpoints)} market data endpoints")

    Mix.shell().info("Writing to generated_market_data_endpoints.ex...")
    write_endpoints(endpoints)

    Mix.shell().info("✅ Successfully generated #{length(endpoints)} Bybit market data endpoints")
    Mix.shell().info("📝 Output: lib/zen_cex/adapters/bybit/generated_market_data_endpoints.ex")
  end

  defp fetch_postman_collection do
    case Req.get(@postman_url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Jason.decode!(body)

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        body

      {:error, reason} ->
        Mix.raise("Failed to download Postman collection: #{inspect(reason)}")
    end
  end

  defp parse_and_filter_endpoints(collection) do
    collection
    |> extract_all_endpoints()
    |> filter_market_data_endpoints()
    |> Enum.map(&convert_to_endpoint_spec/1)
    |> Enum.sort_by(& &1.operation)
  end

  defp extract_all_endpoints(collection) do
    collection
    |> Map.get("item", [])
    |> Enum.flat_map(&extract_items/1)
  end

  defp extract_items(%{"item" => items}) when is_list(items) do
    Enum.flat_map(items, &extract_items/1)
  end

  defp extract_items(%{"request" => request} = item) do
    [%{request: request, name: Map.get(item, "name", "")}]
  end

  defp extract_items(_), do: []

  defp filter_market_data_endpoints(items) do
    Enum.filter(items, fn %{request: request} ->
      path = extract_path(request)
      market_data_endpoint?(path)
    end)
  end

  defp extract_path(%{"url" => %{"raw" => raw}}) do
    case Regex.run(~r{(/v5/[^?]+)}, raw) do
      [_, path] -> path
      _ -> ""
    end
  end

  defp extract_path(_), do: ""

  defp market_data_endpoint?(path) do
    Enum.any?(market_data_patterns(), &Regex.match?(&1, path))
  end

  defp convert_to_endpoint_spec(%{request: request, name: name}) do
    path = extract_path(request)
    method = extract_method(request)
    operation = generate_operation_name(path, name)

    %{
      operation: operation,
      method: method,
      path: path,
      # Market data is always public
      requires_auth: false,
      weight: @default_rate_limit_weight,
      timeout: @default_public_timeout_ms,
      max_retries: @default_max_retries_public,
      retry_on: [:timeout, :network_error],
      response_parser: "&Parser.parse_market_data_response/1",
      error_mapping: "&Parser.parse_error/1",
      doc: name
    }
  end

  defp extract_method(%{"method" => method}) do
    method
    |> String.downcase()
    |> String.to_atom()
  end

  defp extract_method(_), do: :get

  defp generate_operation_name(path, _name) do
    # Extract the key part after /v5/market/
    operation_part =
      path
      |> String.replace("/v5/market/", "")
      |> String.replace("-", "_")
      |> String.replace("/", "_")

    # Clean up the operation name - be more specific for different kline types
    base_name =
      cond do
        path == "/v5/market/kline" -> "get_klines"
        path == "/v5/market/mark-price-kline" -> "get_mark_price_klines"
        path == "/v5/market/index-price-kline" -> "get_index_price_klines"
        path == "/v5/market/premium-index-price-kline" -> "get_premium_index_klines"
        String.contains?(path, "orderbook") -> "get_orderbook"
        String.contains?(path, "tickers") -> "get_tickers"
        String.contains?(path, "recent-trade") -> "get_recent_trades"
        String.contains?(path, "open-interest") -> "get_open_interest"
        String.contains?(path, "funding/history") -> "get_funding_history"
        String.contains?(path, "instruments-info") -> "get_instruments_info"
        String.contains?(path, "risk-limit") -> "get_risk_limit"
        String.contains?(path, "delivery-price") -> "get_delivery_price"
        String.contains?(path, "historical-volatility") -> "get_historical_volatility"
        String.contains?(path, "insurance") -> "get_insurance_info"
        true -> sanitize_operation_name(operation_part)
      end

    String.to_atom(base_name)
  end

  defp sanitize_operation_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.trim("_")
  end

  defp write_endpoints(endpoints) do
    timestamp = DateTime.utc_now()

    content = """
    # Generated from Bybit v5 Postman collection - MARKET DATA
    # DO NOT EDIT - This file was auto-generated by Mix.Tasks.ZenCex.GenerateBybitMarketData
    # Generated at: #{timestamp}
    # Run `mix zen_cex.generate_bybit_market_data` to regenerate

    [
    #{format_endpoints(endpoints)}
    ]
    """

    output_path = "lib/zen_cex/adapters/bybit/generated_market_data_endpoints.ex"
    File.write!(output_path, content)
  end

  defp format_endpoints(endpoints) do
    Enum.map_join(endpoints, ",\n", &format_single_endpoint/1)
  end

  defp format_single_endpoint(endpoint) do
    """
      %{
        operation: :#{endpoint.operation},
        method: :#{endpoint.method},
        path: "#{endpoint.path}",
        requires_auth: #{endpoint.requires_auth},
        weight: #{endpoint.weight},
        timeout: #{endpoint.timeout},
        max_retries: #{endpoint.max_retries},
        retry_on: #{inspect(endpoint.retry_on)},
        response_parser: #{endpoint.response_parser},
        error_mapping: #{endpoint.error_mapping},
        doc: "#{endpoint.doc}"
      }\
    """
  end
end
