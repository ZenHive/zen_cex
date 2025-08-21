defmodule Mix.Tasks.ZenCex.GenerateMarginEndpoints do
  @shortdoc "Generate margin endpoint definitions from Postman collection"
  @moduledoc """
  Generates margin endpoint definitions from Binance Postman collection.

  ## Usage

      mix zen_cex.generate_margin_endpoints [--output path]

  ## Options

    * `--output` - Output file path (default: lib/zen_cex/adapters/binance/generated_margin_endpoints.ex)

  ## Examples

      mix zen_cex.generate_margin_endpoints
      mix zen_cex.generate_margin_endpoints --output lib/custom_endpoints.ex

  """

  use Mix.Task

  # Default timeout for generated endpoints in milliseconds
  @default_endpoint_timeout_ms 5_000

  # Core margin trading operations - skip market data
  @trading_operations [
    # Account operations
    "account",
    "balance",
    "capital",
    "isolated",
    "cross",
    "leverage",
    "margin",
    # Transfer operations
    "transfer",
    # Loan operations
    "loan",
    "borrow",
    "repay",
    "interest",
    # Order operations
    "order",
    "orders",
    "cancel",
    # Trade history
    "trades",
    "myTrades",
    # OCO operations
    "orderList",
    "allOrderList",
    # Risk management
    "tradeCoeff",
    "maxBorrowable",
    "maxTransferable",
    # BNB burn
    "bnbBurn"
  ]

  @skip_operations [
    # Market data operations we don't want
    "klines",
    "ticker",
    "depth",
    "trades",
    "aggTrades",
    "bookTicker",
    # System operations we already have
    "ping",
    "time",
    "exchangeInfo"
  ]

  @doc """
  Runs the margin endpoint generation task.

  Accepts optional output path parameter.
  """
  @spec run([String.t()]) :: :ok
  def run(args) do
    # Start the application to ensure Req/Finch are available
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [output: :string])

    generate_margin_endpoints(opts)
  end

  defp generate_margin_endpoints(opts) do
    output_path = opts[:output] || "lib/zen_cex/adapters/binance/generated_margin_endpoints.ex"

    collection_url =
      "https://raw.githubusercontent.com/binance/binance-api-postman/refs/heads/master/collections/Binance%20Margin%20Trading%20API.json"

    Mix.shell().info("Downloading Postman collection from #{collection_url}...")

    collection_json = fetch_postman_collection(collection_url)
    Mix.shell().info("Parsing Postman collection...")

    endpoints =
      collection_json
      |> Jason.decode!()
      |> extract_trading_endpoints()
      |> map_postman_to_endpoint_format()
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
    collection
    |> Map.get("item", [])
    |> Enum.flat_map(&extract_from_folder/1)
    |> Enum.filter(&trading_endpoint?/1)
  end

  defp extract_from_folder(%{"item" => items} = folder) do
    # Recursively extract from nested folders
    Enum.flat_map(items, fn item ->
      case item do
        %{"request" => _} = endpoint ->
          # Add folder context to endpoint
          [Map.put(endpoint, "folder_name", folder["name"])]

        %{"item" => _} ->
          # Nested folder
          extract_from_folder(item)

        _ ->
          []
      end
    end)
  end

  defp extract_from_folder(%{"request" => _} = endpoint) do
    # Direct endpoint without folder
    [endpoint]
  end

  defp extract_from_folder(_), do: []

  defp trading_endpoint?(%{"request" => %{"url" => url}}) when is_map(url) do
    path = get_path_from_url(url)

    # Check if it's a trading operation and not a skip operation
    is_trading = Enum.any?(@trading_operations, &String.contains?(path, &1))
    is_skip = Enum.any?(@skip_operations, &String.contains?(path, &1))

    is_trading and not is_skip
  end

  defp trading_endpoint?(_), do: false

  defp get_path_from_url(%{"raw" => raw}) when is_binary(raw) do
    # Extract path from raw URL, removing the {{url}} placeholder
    cleaned = String.replace(raw, "{{url}}", "")

    case URI.parse(cleaned) do
      %URI{path: path} when is_binary(path) ->
        path

      _ ->
        # If parsing fails, try to extract path directly
        case String.split(cleaned, "/sapi") do
          [_, rest] -> "/sapi" <> rest
          _ -> cleaned
        end
    end
  end

  defp get_path_from_url(%{"path" => path}) when is_list(path) do
    # Join path segments
    "/" <> Enum.join(path, "/")
  end

  defp get_path_from_url(_), do: ""

  defp map_postman_to_endpoint_format(endpoints) do
    Enum.map(endpoints, &convert_endpoint/1)
  end

  defp convert_endpoint(%{"request" => request} = endpoint) do
    url = request["url"]
    path = get_path_from_url(url)
    method = request["method"] |> String.downcase() |> String.to_atom()

    # Generate operation name from path
    operation = generate_operation_name(method, path)

    # Check if auth is required (has headers with API key)
    requires_auth = has_api_key_header?(request)

    # Extract description
    doc = endpoint["name"] || "No description"

    %{
      operation: operation,
      method: method,
      path: path,
      requires_auth: requires_auth,
      weight: determine_weight(path),
      timeout: @default_endpoint_timeout_ms,
      max_retries: determine_max_retries(operation),
      retry_on: determine_retry_on(operation),
      response_parser: "&Parser.parse_generic/1",
      error_mapping: "&Parser.parse_error/1",
      doc: doc
    }
  end

  defp generate_operation_name(method, path) do
    # Extract meaningful part from path
    parts =
      path
      |> String.split("/")
      |> Enum.filter(&(&1 != "" and not String.starts_with?(&1, "v")))
      # Drop "sapi"
      |> Enum.drop(1)
      # Drop "margin"
      |> Enum.drop(1)

    # Build operation name
    operation_parts =
      case method do
        :get -> ["get" | parts]
        :post -> ["place" | parts]
        :delete -> ["cancel" | parts]
        :put -> ["update" | parts]
        _ -> [Atom.to_string(method) | parts]
      end

    operation_parts
    |> Enum.map_join("_", &String.replace(&1, "-", "_"))
    |> String.to_atom()
  end

  defp has_api_key_header?(%{"header" => headers}) when is_list(headers) do
    Enum.any?(headers, fn
      %{"key" => "X-MBX-APIKEY"} -> true
      _ -> false
    end)
  end

  # Default to requiring auth for safety
  defp has_api_key_header?(_), do: true

  defp determine_weight(path) do
    cond do
      String.contains?(path, "order") -> 5
      String.contains?(path, "account") -> 20
      String.contains?(path, "trades") -> 20
      String.contains?(path, "transfer") -> 1
      String.contains?(path, "borrow") -> 10
      String.contains?(path, "repay") -> 10
      true -> 1
    end
  end

  defp determine_max_retries(operation) do
    case operation do
      # Never retry orders
      op when op in [:place_order, :place_orderList] -> 0
      # Allow one retry for cancels
      op when op in [:cancel_order, :cancel_orders] -> 1
      # Default retries for queries
      _ -> 3
    end
  end

  defp determine_retry_on(operation) do
    case operation do
      # No retries
      op when op in [:place_order, :place_orderList] -> []
      op when op in [:cancel_order, :cancel_orders] -> [:timeout]
      _ -> [:rate_limited, :timeout, :server_error]
    end
  end

  defp add_smart_defaults(endpoints) do
    Enum.map(endpoints, fn endpoint ->
      # Update parser based on operation
      endpoint =
        case endpoint.operation do
          :get_account ->
            %{endpoint | response_parser: "&Parser.parse_margin_account/1"}

          :get_isolated_account ->
            %{endpoint | response_parser: "&Parser.parse_isolated_account/1"}

          op when op in [:place_order, :cancel_order] ->
            %{endpoint | response_parser: "&Parser.parse_order/1"}

          op when op in [:get_loan, :get_repay, :get_interest] ->
            %{endpoint | response_parser: "&Parser.parse_loan_record/1"}

          _ ->
            endpoint
        end

      endpoint
    end)
  end

  defp format_as_elixir_data(endpoints) do
    """
    # Generated by mix zen_cex.generate_margin_endpoints
    # DO NOT EDIT - Regenerate using: mix zen_cex.generate_margin_endpoints

    [
    #{format_endpoints(endpoints)}
    ]
    """
  end

  defp format_endpoints(endpoints) do
    Enum.map_join(endpoints, ",\n", &format_single_endpoint/1)
  end

  defp format_single_endpoint(endpoint) do
    """
      %{
        operation: #{inspect(endpoint.operation)},
        method: #{inspect(endpoint.method)},
        path: #{inspect(endpoint.path)},
        requires_auth: #{endpoint.requires_auth},
        weight: #{endpoint.weight},
        timeout: #{endpoint.timeout},
        max_retries: #{endpoint.max_retries},
        retry_on: #{inspect(endpoint.retry_on)},
        response_parser: #{endpoint.response_parser},
        error_mapping: #{endpoint.error_mapping},
        doc: #{inspect(endpoint.doc)}
      }\
    """
  end
end
