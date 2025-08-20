defmodule Mix.Tasks.ZenCex.GenerateEndpoints do
  @shortdoc "Generate endpoint definitions from OpenAPI specs"
  @moduledoc """
  Generates endpoint definitions from OpenAPI specifications.

  ## Usage

      mix zen_cex.generate_endpoints binance [--output path]

  ## Options

    * `--output` - Output file path (default: lib/zen_cex/adapters/{exchange}/generated_endpoints.ex)

  ## Examples

      mix zen_cex.generate_endpoints binance
      mix zen_cex.generate_endpoints binance --output lib/custom_endpoints.ex

  """

  use Mix.Task

  # Core trading and account operations - skip market data
  @trading_patterns [
    # Account endpoints
    ~r{/api/v3/account},
    ~r{/api/v3/tradingFee},
    ~r{/api/v3/accountStatus},

    # Order management
    # place, cancel, get order
    ~r{/api/v3/order$},
    # get open orders
    ~r{/api/v3/openOrders},
    # order history
    ~r{/api/v3/allOrders},
    # OCO orders
    ~r{/api/v3/orderList},

    # Trade history
    # trade history
    ~r{/api/v3/myTrades},
    # OCO history
    ~r{/api/v3/allOrderList},

    # Test connectivity (useful for health checks)
    ~r{/api/v3/ping},
    ~r{/api/v3/time}
  ]

  @doc """
  Runs the endpoint generation task for the specified exchange.

  Accepts an exchange name and optional output path parameter.
  """
  @spec run([String.t()]) :: :ok
  def run(args) do
    # Start the application to ensure Req/Finch are available
    Mix.Task.run("app.start")

    {opts, [exchange | _], _} = OptionParser.parse(args, strict: [output: :string])

    case exchange do
      "binance" -> generate_binance_endpoints(opts)
      _ -> Mix.shell().error("Unsupported exchange: #{exchange}")
    end
  end

  defp generate_binance_endpoints(opts) do
    output_path = opts[:output] || "lib/zen_cex/adapters/binance/generated_endpoints.ex"

    Mix.shell().info("Downloading Binance OpenAPI specification...")

    yaml_content = fetch_binance_openapi()
    Mix.shell().info("Parsing OpenAPI specification...")

    endpoints =
      yaml_content
      |> parse_yaml()
      |> filter_trading_endpoints()
      |> map_to_endpoint_format()
      |> add_smart_defaults()

    Mix.shell().info("Generating #{length(endpoints)} endpoint definitions...")

    generated_code = format_as_elixir_module(endpoints)

    File.write!(output_path, generated_code)
    Mix.shell().info("Generated endpoints written to: #{output_path}")

    # Show summary
    operations = Enum.map(endpoints, & &1.operation)
    Mix.shell().info("Generated operations: #{inspect(operations, pretty: true)}")
  end

  defp fetch_binance_openapi do
    url = "https://raw.githubusercontent.com/binance/binance-api-swagger/master/spot_api.yaml"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        body

      {:ok, %{status: status}} ->
        Mix.raise("Failed to download OpenAPI spec: HTTP #{status}")

      {:error, reason} ->
        Mix.raise("Failed to download OpenAPI spec: #{inspect(reason)}")
    end
  end

  defp parse_yaml(yaml_content) do
    # Check if YamlElixir module is available
    if function_exported?(YamlElixir, :read_from_string, 1) do
      YamlElixir
      |> apply(:read_from_string, [yaml_content])
      |> case do
        {:ok, data} ->
          data

        {:error, reason} ->
          Mix.raise("Failed to parse YAML: #{inspect(reason)}")
      end
    else
      Mix.raise("""
      YamlElixir is not available. Please add it to your dependencies:

      In mix.exs, add to deps:
        {:yaml_elixir, "~> 2.9", only: :dev}

      Then run:
        mix deps.get

      This dependency is only needed for generating endpoints from OpenAPI specs.
      """)
    end
  end

  defp filter_trading_endpoints(openapi_spec) do
    paths = openapi_spec["paths"] || %{}

    paths
    |> Enum.filter(fn {path, _operations} ->
      Enum.any?(@trading_patterns, &Regex.match?(&1, path))
    end)
    |> Map.new()
  end

  defp map_to_endpoint_format(filtered_paths) do
    Enum.flat_map(filtered_paths, fn {path, operations} ->
      Enum.map(operations, fn {method, spec} ->
        %{
          operation: derive_operation_name(method, path, spec),
          method: String.to_atom(method),
          path: path,
          requires_auth: requires_authentication?(spec),
          weight: extract_weight(spec),
          # Default, will be overridden by smart defaults
          timeout: 5_000,
          # Default, will be overridden by smart defaults
          max_retries: 2,
          # Default
          retry_on: [:rate_limited, :timeout],
          response_parser: derive_parser_function(path, spec),
          error_mapping: :parse_error,
          doc: extract_documentation(spec)
        }
      end)
    end)
  end

  defp derive_operation_name(method, path, spec) do
    # Try operation ID first, then derive from path and method
    operation_id = spec["operationId"]

    if operation_id do
      operation_id |> Macro.underscore() |> String.to_atom()
    else
      # Derive from path and method
      path_part =
        path
        |> String.replace(~r{/api/v\d+/}, "")
        # Remove path parameters
        |> String.replace(~r/[{}]/, "")

      method_prefix =
        case method do
          "get" ->
            "get"

          "post" ->
            if String.contains?(path, "order"), do: "place", else: "create"

          "put" ->
            "update"

          "delete" ->
            if String.contains?(path, "order"), do: "cancel", else: "delete"
        end

      String.to_atom("#{method_prefix}_#{path_part}")
    end
  end

  defp requires_authentication?(spec) do
    security = spec["security"] || []
    not Enum.empty?(security)
  end

  defp extract_weight(spec) do
    # First check for x-weight extension
    case spec["x-weight"] do
      weight when is_integer(weight) ->
        weight

      weight when is_binary(weight) ->
        String.to_integer(weight)

      _ ->
        # Try to extract weight from description/summary
        extract_weight_from_docs(spec)
    end
  rescue
    _ -> 1
  end

  defp extract_weight_from_docs(spec) do
    # Check both description and summary for weight information
    text = "#{spec["description"] || ""} #{spec["summary"] || ""}"

    # Look for patterns like "Weight(IP): 20" or "Weight: 10"
    case Regex.run(~r/Weight\s*\(?\s*IP\s*\)?\s*:\s*(\d+)/i, text) do
      [_, weight_str] ->
        String.to_integer(weight_str)

      _ ->
        # Default weight if not found
        1
    end
  end

  defp derive_parser_function(path, _spec) do
    cond do
      String.contains?(path, "account") -> :parse_account
      String.contains?(path, "order") -> :parse_order
      String.contains?(path, "myTrades") -> :parse_trades
      String.contains?(path, "tradingFee") -> :parse_fees
      true -> :parse_generic
    end
  end

  defp extract_documentation(spec) do
    summary = spec["summary"] || ""
    description = spec["description"] || ""

    case {summary, description} do
      {"", ""} -> "Generated endpoint"
      {summary, ""} -> summary
      {"", description} -> description
      {summary, description} -> "#{summary}\n\n#{description}"
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
        op when op in [:place_order, :cancel_order, :place_order_list, :cancel_order_list] ->
          # Fast timeout for trading operations
          2_000

        _ ->
          # Standard timeout for queries
          5_000
      end

    %{endpoint | timeout: timeout}
  end

  defp add_retry_by_safety(endpoint) do
    case endpoint.method do
      :get ->
        # Safe to retry GET requests
        %{endpoint | max_retries: 3, retry_on: [:rate_limited, :timeout, :server_error]}

      _ when endpoint.operation in [:place_order, :place_order_list] ->
        # NEVER retry order placement - could create duplicate orders
        %{endpoint | max_retries: 0, retry_on: []}

      _ ->
        # Other POST/DELETE operations can retry on specific errors
        %{endpoint | max_retries: 1, retry_on: [:timeout]}
    end
  end

  defp format_as_elixir_module(endpoints) do
    endpoints_list = Enum.map_join(endpoints, ",\n", &format_endpoint/1)

    "# Generated by mix zen_cex.generate_endpoints binance\n" <>
      "# DO NOT EDIT - Regenerate using: mix zen_cex.generate_endpoints binance\n\n" <>
      "[\n" <>
      endpoints_list <>
      "\n]"
  end

  defp format_endpoint(endpoint) do
    doc = String.replace(endpoint.doc, "\"", "\\\"")

    "  %{\n" <>
      "    operation: #{inspect(endpoint.operation)},\n" <>
      "    method: #{inspect(endpoint.method)},\n" <>
      "    path: #{inspect(endpoint.path)},\n" <>
      "    requires_auth: #{endpoint.requires_auth},\n" <>
      "    weight: #{endpoint.weight},\n" <>
      "    timeout: #{endpoint.timeout},\n" <>
      "    max_retries: #{endpoint.max_retries},\n" <>
      "    retry_on: #{inspect(endpoint.retry_on)},\n" <>
      "    response_parser: &Parser.#{endpoint.response_parser}/1,\n" <>
      "    error_mapping: &Parser.#{endpoint.error_mapping}/1,\n" <>
      "    doc: \"#{doc}\"\n" <>
      "  }"
  end
end
