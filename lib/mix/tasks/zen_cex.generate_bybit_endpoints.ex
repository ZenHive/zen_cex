defmodule Mix.Tasks.ZenCex.GenerateBybitEndpoints do
  @shortdoc "Generate Bybit v5 endpoint definitions from Postman collection"
  @moduledoc """
  Generates Bybit v5 unified endpoint definitions from the official Postman collection.

  ## Usage

      mix zen_cex.generate_bybit_endpoints

  ## What it does

  1. Downloads the Bybit v5 Postman collection from GitHub
  2. Filters for trading-related endpoints only (ignores market data)
  3. Generates endpoint definitions in the Bybit adapter format
  4. Writes to `lib/zen_cex/adapters/bybit/generated_endpoints.ex`

  ## Endpoints included

  - Account management (wallet, fees, collateral)
  - Order management (create, amend, cancel, history)
  - Position management (list, leverage, stops)
  - Trade execution history
  - Asset management (deposits, withdrawals, transfers)

  ## Endpoints excluded

  - Market data (klines, orderbook, tickers)
  - Public information endpoints
  """

  use Mix.Task

  # Timeout constants for different operation types
  # Fast timeout for trading operations
  @trading_timeout_ms 2_000
  # Moderate timeout for account queries
  @query_timeout_ms 3_000
  # Default timeout for standard operations
  @standard_timeout_ms 5_000

  # Retry configuration constants
  # Maximum retries for safe operations
  @max_retries_safe 3
  # Maximum retries for order modifications
  @max_retries_modify 1
  # Default maximum retries
  @max_retries_default 2
  # No retries for order placement
  @no_retries 0

  # Postman collection URL
  @postman_url "https://raw.githubusercontent.com/bybit-exchange/QuickStartWithPostman/refs/heads/main/V5APIs/Open%20API%20V5.postman_collection.json"

  @doc """
  Runs the Bybit endpoint generation task.
  """
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Downloading Bybit v5 Postman collection...")
    collection = fetch_postman_collection()

    Mix.shell().info("Parsing and filtering trading endpoints...")
    endpoints = parse_and_filter_endpoints(collection)

    Mix.shell().info("Found #{length(endpoints)} trading endpoints")

    generated_code = generate_elixir_code(endpoints)
    output_path = "lib/zen_cex/adapters/bybit/generated_endpoints.ex"

    File.write!(output_path, generated_code)
    Mix.shell().info("Generated endpoints written to: #{output_path}")

    # Show summary
    operations = endpoints |> Enum.map(& &1.operation) |> Enum.sort() |> Enum.uniq()
    Mix.shell().info("\nGenerated #{length(operations)} unique operations:")
    Enum.each(operations, fn op -> Mix.shell().info("  - #{op}") end)
  end

  defp fetch_postman_collection do
    case Req.get(@postman_url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Jason.decode!(body)

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        body

      {:ok, %{status: status}} ->
        Mix.raise("Failed to download Postman collection: HTTP #{status}")

      {:error, reason} ->
        Mix.raise("Failed to download Postman collection: #{inspect(reason)}")
    end
  end

  defp parse_and_filter_endpoints(collection) do
    collection
    |> extract_all_requests()
    |> filter_non_market_data_endpoints()
    |> map_to_endpoint_format()
    |> add_smart_defaults()
    |> deduplicate_endpoints()
  end

  defp extract_all_requests(collection) do
    items = collection["item"] || []

    Enum.flat_map(items, fn item ->
      case item do
        %{"request" => request} when is_map(request) ->
          # Direct request item
          [{request, item}]

        %{"item" => subitems} when is_list(subitems) ->
          # Folder with nested items
          Enum.flat_map(subitems, fn subitem ->
            case subitem do
              %{"request" => request} when is_map(request) ->
                [{request, subitem}]

              %{"item" => subsubitems} when is_list(subsubitems) ->
                # Nested folder
                Enum.flat_map(subsubitems, fn subsubitem ->
                  case subsubitem do
                    %{"request" => request} when is_map(request) ->
                      [{request, subsubitem}]

                    _ ->
                      []
                  end
                end)

              _ ->
                []
            end
          end)

        _ ->
          []
      end
    end)
  end

  defp filter_non_market_data_endpoints(requests) do
    # Only exclude market data endpoints - keep everything else
    # Market data is handled by generate_bybit_market_data.ex
    Enum.reject(requests, fn {request, _item} ->
      path = extract_path(request)
      String.contains?(path, "/v5/market/")
    end)
  end

  defp extract_path(request) do
    url = request["url"]

    case url do
      %{"raw" => raw} when is_binary(raw) ->
        # Extract path from full URL, removing Postman variables
        raw
        |> String.replace("{{url}}", "")
        |> URI.parse()
        |> Map.get(:path, "/")

      %{"path" => path} when is_list(path) ->
        # Reconstruct from path segments
        "/" <> Enum.join(path, "/")

      _ ->
        "/"
    end
  end

  defp map_to_endpoint_format(requests) do
    Enum.map(requests, fn {request, item} ->
      method = String.downcase(request["method"] || "get")
      path = extract_path(request)
      name = item["name"] || "Unknown"

      %{
        operation: derive_operation_name(method, path, name),
        method: String.to_atom(method),
        path: clean_path(path),
        requires_auth: requires_authentication?(request),
        # Bybit doesn't have weights in Postman
        weight: 1,
        timeout: @standard_timeout_ms,
        max_retries: @max_retries_default,
        retry_on: [:timeout],
        response_parser: :parse_unified_response,
        error_mapping: :parse_error,
        doc: extract_documentation(item)
      }
    end)
  end

  defp derive_operation_name(method, path, name) do
    # Special handling for common order operations
    cond do
      String.contains?(path, "/order/create-batch") ->
        :place_batch_orders

      String.contains?(path, "/order/create") and String.contains?(name, "Limit") ->
        :place_limit_order

      String.contains?(path, "/order/create") and String.contains?(name, "Market") ->
        :place_market_order

      String.contains?(path, "/order/create") and String.contains?(name, "Conditional") ->
        :place_conditional_order

      String.contains?(path, "/order/create") ->
        :place_order

      String.contains?(path, "/order/cancel-batch") ->
        :cancel_batch_orders

      String.contains?(path, "/order/cancel-all") ->
        :cancel_all_orders

      String.contains?(path, "/order/cancel") and not String.contains?(path, "all") ->
        :cancel_order

      String.contains?(path, "/order/amend-batch") ->
        :amend_batch_orders

      String.contains?(path, "/order/amend") ->
        :amend_order

      true ->
        # Generic derivation
        clean_name =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9_]/, "_")
          |> String.replace(~r/_+/, "_")
          |> String.trim("_")

        # If name is too generic, derive from path
        if clean_name in ["", "unknown", "request", "create", "cancel", "amend"] do
          path_based_name(method, path)
        else
          # Ensure the name starts with a verb
          if String.starts_with?(clean_name, ["get_", "create_", "cancel_", "amend_", "list_", "set_", "switch_"]) do
            String.to_atom(clean_name)
          else
            verb = method_to_verb(method, path)
            String.to_atom("#{verb}_#{clean_name}")
          end
        end
    end
  end

  defp path_based_name(method, path) do
    # Extract meaningful parts from path
    path_parts =
      path
      |> String.replace(~r{^/v5/}, "")
      |> String.split("/")
      |> Enum.reject(&(&1 == ""))

    verb = method_to_verb(method, path)
    noun = Enum.join(path_parts, "_")

    String.to_atom("#{verb}_#{noun}")
  end

  defp method_to_verb(method, path) do
    case method do
      "get" ->
        "get"

      "post" ->
        cond do
          String.contains?(path, "create") -> "create"
          String.contains?(path, "cancel") -> "cancel"
          String.contains?(path, "amend") -> "amend"
          String.contains?(path, "place") -> "place"
          String.contains?(path, "set") -> "set"
          String.contains?(path, "switch") -> "switch"
          String.contains?(path, "add") -> "add"
          String.contains?(path, "confirm") -> "confirm"
          true -> "create"
        end

      "delete" ->
        "delete"

      _ ->
        method
    end
  end

  defp clean_path(path) do
    # Remove any query parameters and ensure consistent format
    path
    |> String.split("?")
    |> List.first()
    # Remove any remaining Postman URL variables
    |> String.replace(":{{url}}", "")
    |> String.replace("{{url}}", "")
    # Convert {param} to {:param} format if needed
    |> String.replace(~r/\{([^}]+)\}/, ":{\\1}")
    # Ensure path starts with /
    |> then(fn p -> if String.starts_with?(p, "/"), do: p, else: "/" <> p end)
  end

  defp requires_authentication?(request) do
    # Check if request has auth headers
    headers = request["header"] || []

    auth_headers = ["X-BAPI-API-KEY", "X-BAPI-SIGN", "X-BAPI-TIMESTAMP"]

    Enum.any?(headers, fn header ->
      header["key"] in auth_headers
    end)
  end

  defp extract_documentation(item) do
    description = item["description"] || ""
    name = item["name"] || ""

    case_result =
      case {name, description} do
        {"", ""} -> "Bybit v5 API endpoint"
        {name, ""} -> name
        {"", desc} -> desc
        {name, desc} -> "#{name}. #{desc}"
      end

    case_result
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp add_smart_defaults(endpoints) do
    Enum.map(endpoints, fn endpoint ->
      endpoint
      |> add_timeout_by_operation()
      |> add_retry_policy()
    end)
  end

  defp add_timeout_by_operation(endpoint) do
    timeout =
      case endpoint.operation do
        op
        when op in [
               :create_order,
               :place_order,
               :place_limit_order,
               :place_market_order,
               :place_conditional_order,
               :cancel_order,
               :amend_order
             ] ->
          @trading_timeout_ms

        op when op in [:get_wallet_balance, :get_position_list] ->
          @query_timeout_ms

        _ ->
          @standard_timeout_ms
      end

    %{endpoint | timeout: timeout}
  end

  defp add_retry_policy(endpoint) do
    case {endpoint.method, endpoint.operation} do
      {:get, _} ->
        # Safe to retry GET requests
        %{endpoint | max_retries: @max_retries_safe, retry_on: [:timeout, :server_error]}

      {_, op}
      when op in [
             :create_order,
             :place_order,
             :place_limit_order,
             :place_market_order,
             :place_conditional_order,
             :place_batch_orders
           ] ->
        # NEVER retry order placement
        %{endpoint | max_retries: @no_retries, retry_on: []}

      {_, op} when op in [:amend_order, :amend_batch_orders] ->
        # No retry for order amendments to avoid duplicate modifications
        %{endpoint | max_retries: @no_retries, retry_on: []}

      {_, op} when op in [:cancel_order, :cancel_batch_orders] ->
        # Careful retry for order cancellations (idempotent operations)
        %{endpoint | max_retries: @max_retries_modify, retry_on: [:timeout]}

      _ ->
        # Default retry policy
        %{endpoint | max_retries: @max_retries_default, retry_on: [:timeout]}
    end
  end

  defp deduplicate_endpoints(endpoints) do
    # Group by operation and keep all unique paths
    # Don't deduplicate if paths are different - they're different endpoints
    endpoints
    |> Enum.uniq_by(fn endpoint ->
      {endpoint.operation, endpoint.method, endpoint.path}
    end)
    |> Enum.sort_by(fn endpoint ->
      {endpoint.operation, endpoint.path}
    end)
  end

  defp generate_elixir_code(endpoints) do
    timestamp = to_string(DateTime.utc_now())

    endpoints_code = Enum.map_join(endpoints, ",\n", &format_endpoint/1)

    """
    # Generated from Bybit v5 Postman collection
    # DO NOT EDIT - This file was auto-generated by Mix.Tasks.ZenCex.GenerateBybitEndpoints
    # Generated at: #{timestamp}
    # Run `mix zen_cex.generate_bybit_endpoints` to regenerate

    [
    #{endpoints_code}
    ]
    """
  end

  defp format_endpoint(endpoint) do
    doc = String.replace(endpoint.doc, "\"", "\\\"")

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
        response_parser: &Parser.#{endpoint.response_parser}/1,
        error_mapping: &Parser.#{endpoint.error_mapping}/1,
        doc: "#{doc}"
      }\
    """
  end
end
