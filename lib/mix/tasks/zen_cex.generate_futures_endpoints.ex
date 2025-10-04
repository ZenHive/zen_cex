defmodule Mix.Tasks.ZenCex.GenerateFuturesEndpoints do
  @shortdoc "Generate futures endpoint definitions from Postman collections"
  @moduledoc """
  Generates futures endpoint definitions from Binance Postman collections.

  ## Usage

      mix zen_cex.generate_futures_endpoints usdm [--output path]
      mix zen_cex.generate_futures_endpoints coinm [--output path]
      mix zen_cex.generate_futures_endpoints portfolio [--output path]

  ## Options

    * `--output` - Output file path (default: lib/zen_cex/adapters/binance/generated_{type}_endpoints.ex)

  ## Examples

      mix zen_cex.generate_futures_endpoints usdm
      mix zen_cex.generate_futures_endpoints coinm --output lib/custom_endpoints.ex
      mix zen_cex.generate_futures_endpoints portfolio

  """

  use Mix.Task

  # Default timeout for generated endpoints in milliseconds
  @default_endpoint_timeout_ms 5_000

  # Core trading and account operations - skip market data
  @trading_operations [
    # Account operations
    "account",
    "commission",
    "balance",
    "position",
    "leverage",
    "margin",
    # Order operations
    "order",
    "orders",
    "cancel",
    "modify",
    # Trade history
    "trades",
    "income",
    "fills"
  ]

  @skip_operations [
    # Market data operations we don't want
    "klines",
    "ticker",
    "depth",
    "trades",
    "aggTrades",
    "fundingRate",
    "markPrice",
    "premiumIndex",
    "openInterest",
    "indexPrice",
    # System info we don't need
    "exchangeInfo"
  ]

  @doc """
  Runs the futures endpoint generation task for the specified type.

  Accepts a futures type (usdm, coinm, or portfolio) and optional output path parameter.
  """
  @spec run([String.t()]) :: :ok
  def run(args) do
    # Start the application to ensure Req/Finch are available
    Mix.Task.run("app.start")

    {opts, positional, _} = OptionParser.parse(args, strict: [output: :string])

    case positional do
      [futures_type | _] ->
        case futures_type do
          "usdm" -> generate_usdm_endpoints(opts)
          "coinm" -> generate_coinm_endpoints(opts)
          "portfolio" -> generate_portfolio_endpoints(opts)
          _ -> Mix.shell().error("Unsupported futures type: #{futures_type}. Use 'usdm', 'coinm', or 'portfolio'")
        end

      [] ->
        # Generate all three types if no specific type provided
        Mix.shell().info("No futures type specified. Generating all types (usdm, coinm, portfolio)...")
        generate_usdm_endpoints(opts)
        generate_coinm_endpoints(opts)
        generate_portfolio_endpoints(opts)
    end
  end

  defp generate_usdm_endpoints(opts) do
    output_path = opts[:output] || "lib/zen_cex/adapters/binance/generated_usdm_endpoints.ex"

    collection_url =
      "https://raw.githubusercontent.com/binance/binance-api-postman/master/collections/Binance%20Derivatives%20Trading%20USDS%20Futures%20API.json"

    generate_from_postman(collection_url, output_path, :usdm_futures)
  end

  defp generate_coinm_endpoints(opts) do
    output_path = opts[:output] || "lib/zen_cex/adapters/binance/generated_coinm_endpoints.ex"

    collection_url =
      "https://raw.githubusercontent.com/binance/binance-api-postman/master/collections/Binance%20Derivatives%20Trading%20COIN%20Futures%20API.json"

    generate_from_postman(collection_url, output_path, :coinm_futures)
  end

  defp generate_portfolio_endpoints(opts) do
    output_path = opts[:output] || "lib/zen_cex/adapters/binance/generated_portfolio_endpoints.ex"

    collection_url =
      "https://raw.githubusercontent.com/binance/binance-api-postman/master/collections/Binance%20Derivatives%20Trading%20Portfolio%20Margin%20API.json"

    generate_from_postman(collection_url, output_path, :portfolio)
  end

  defp generate_from_postman(collection_url, output_path, api_type) do
    Mix.shell().info("Downloading Postman collection from #{collection_url}...")

    collection_json = fetch_postman_collection(collection_url)
    Mix.shell().info("Parsing Postman collection...")

    endpoints =
      collection_json
      |> Jason.decode!()
      |> extract_trading_endpoints()
      |> map_postman_to_endpoint_format(api_type)
      |> add_smart_defaults()
      # Remove duplicates
      |> Enum.uniq_by(& &1.operation)

    Mix.shell().info("Generating #{length(endpoints)} endpoint definitions...")

    generated_code = format_as_elixir_data(endpoints)

    File.write!(output_path, generated_code)
    Mix.shell().info("Generated endpoints written to: #{output_path}")

    # Show summary
    operations = Enum.map(endpoints, & &1.operation)
    Mix.shell().info("Generated operations: #{inspect(operations, pretty: true, limit: :infinity)}")
  end

  defp fetch_postman_collection(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        body

      {:ok, %{status: status}} ->
        Mix.raise("Failed to download Postman collection: HTTP #{status}")

      {:error, reason} ->
        Mix.raise("Failed to download Postman collection: #{inspect(reason)}")
    end
  end

  defp extract_trading_endpoints(collection) do
    # Get Account and Trade sections
    account_items = get_section_items(collection, "Account")
    trade_items = get_section_items(collection, "Trade")

    Enum.filter(account_items ++ trade_items, &trading_endpoint?/1)
  end

  defp get_section_items(collection, section_name) do
    collection["item"]
    |> Enum.find(%{}, fn item -> item["name"] == section_name end)
    |> Map.get("item", [])
  end

  defp trading_endpoint?(item) do
    name = String.downcase(item["name"] || "")

    # Check if it's a trading operation
    has_trading = Enum.any?(@trading_operations, &String.contains?(name, &1))

    # Check if it's NOT a market data operation
    not_market_data = not Enum.any?(@skip_operations, &String.contains?(name, &1))

    has_trading and not_market_data
  end

  defp map_postman_to_endpoint_format(items, api_type) do
    Enum.map(items, fn item ->
      request = item["request"]
      url = request["url"]["raw"] || ""
      path = extract_path_from_url(url)

      %{
        operation: derive_operation_from_name(item["name"]),
        method: request["method"] |> String.downcase() |> String.to_atom(),
        path: path,
        api_type: api_type,
        requires_auth: requires_auth?(item["name"]),
        weight: extract_weight_from_name(item["name"]),
        timeout: @default_endpoint_timeout_ms,
        max_retries: 2,
        retry_on: [:rate_limited, :timeout],
        response_parser: derive_parser_from_path(path),
        error_mapping: :parse_error,
        doc: extract_documentation(item)
      }
    end)
  end

  defp extract_path_from_url(url) do
    url
    |> String.replace("{{url}}", "")
    |> String.replace("{{fapi_url}}", "")
    |> String.replace("{{dapi_url}}", "")
    |> String.split("?")
    |> List.first()
  end

  defp derive_operation_from_name(name) do
    name
    # Remove (USER_DATA) etc
    |> String.replace(~r/\([^)]+\)/, "")
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.replace(~r/^_|_$/, "")
    |> then(fn op ->
      # Apply some common transformations
      case op do
        "new_order" -> "place_order"
        "query_order" -> "get_order"
        "cancel_order" -> "cancel_order"
        "current_all_open_orders" -> "get_open_orders"
        "cancel_all_open_orders" -> "cancel_all_orders"
        "futures_account_configuration" -> "get_account_config"
        "futures_account_balance_v3" -> "get_balances"
        "position_information_v3" -> "get_positions"
        "account_trade_list" -> "get_trade_history"
        other -> other
      end
    end)
    |> String.to_atom()
  end

  defp requires_auth?(name) do
    String.contains?(name, "USER_DATA") or String.contains?(name, "TRADE")
  end

  defp extract_weight_from_name(name) do
    # Most futures endpoints have weight 5-20
    cond do
      String.contains?(String.downcase(name), "position") -> 5
      String.contains?(String.downcase(name), "account") -> 10
      String.contains?(String.downcase(name), "order") -> 1
      String.contains?(String.downcase(name), "trade") -> 5
      true -> 5
    end
  end

  defp derive_parser_from_path(path) do
    cond do
      String.contains?(path, "positionRisk") -> :parse_positions
      String.contains?(path, "account") -> :parse_account
      String.contains?(path, "balance") -> :parse_balances
      String.contains?(path, "order") -> :parse_order
      String.contains?(path, "trades") -> :parse_trades
      String.contains?(path, "income") -> :parse_income
      true -> :parse_generic
    end
  end

  defp extract_documentation(item) do
    name = item["name"] || ""
    description = item["request"]["description"] || ""

    # Clean up the name
    clean_name = name |> String.replace(~r/\([^)]+\)/, "") |> String.trim()

    case description do
      "" -> clean_name
      desc -> "#{clean_name}\n\n#{desc}"
    end
  end

  defp add_smart_defaults(endpoints) do
    Enum.map(endpoints, fn endpoint ->
      endpoint
      |> add_timeout_by_type()
      |> add_retry_by_safety()
    end)
  end

  defp add_timeout_by_type(endpoint) do
    timeout =
      case endpoint.operation do
        op when op in [:place_order, :cancel_order, :modify_order] ->
          2_000

        op when op in [:get_positions, :get_balances] ->
          5_000

        _ ->
          5_000
      end

    %{endpoint | timeout: timeout}
  end

  defp add_retry_by_safety(endpoint) do
    case endpoint.method do
      :get ->
        %{endpoint | max_retries: 3, retry_on: [:rate_limited, :timeout, :server_error]}

      _ when endpoint.operation in [:place_order, :modify_order] ->
        # NEVER retry order placement/modification
        %{endpoint | max_retries: 0, retry_on: []}

      _ ->
        # Other POST/DELETE operations can retry on specific errors
        %{endpoint | max_retries: 1, retry_on: [:timeout]}
    end
  end

  defp format_as_elixir_data(endpoints) do
    endpoints_list = Enum.map_join(endpoints, ",\n", &format_endpoint/1)

    """
    # Generated by mix zen_cex.generate_futures_endpoints
    # DO NOT EDIT - Regenerate using the mix task

    [
    #{endpoints_list}
    ]
    """
  end

  defp format_endpoint(endpoint) do
    doc = String.replace(endpoint.doc, "\"", "\\\"")

    # Return just the formatted map structure, not wrapped in triple quotes
    "  %{
    operation: #{inspect(endpoint.operation)},
    method: #{inspect(endpoint.method)},
    path: #{inspect(endpoint.path)},
    api_type: #{inspect(endpoint.api_type)},
    requires_auth: #{endpoint.requires_auth},
    weight: #{endpoint.weight},
    timeout: #{endpoint.timeout},
    max_retries: #{endpoint.max_retries},
    retry_on: #{inspect(endpoint.retry_on)},
    response_parser: &Parser.#{endpoint.response_parser}/1,
    error_mapping: &Parser.#{endpoint.error_mapping}/1,
    doc: \"#{doc}\"
  }"
  end
end
