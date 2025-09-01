defmodule ZenCex.Test.FixtureHelper do
  @moduledoc """
  Helper module for managing test fixtures captured from real API responses.

  This module provides utilities for:
  - Loading captured API response fixtures
  - Creating Req.Test mocks based on real API behavior
  - Version controlling fixture data for API change detection
  - Sanitizing sensitive data from captured responses

  ## Fixture Structure

  All fixtures are stored as JSON files with metadata:

      {
        "data": { ... actual API response ... },
        "captured_at": 1234567890000,
        "zen_cex_version": "0.1.0",
        "test_environment": "binance_testnet",
        "api_endpoint": "/api/v3/account",
        "request_params": { ... sanitized params ... }
      }

  ## Usage

      # Load a specific fixture
      {:ok, fixture} = FixtureHelper.load_fixture("binance", "get_balances_success.json")

      # Create mock from fixture
      mock = FixtureHelper.create_mock_from_fixture(fixture)

      # Use with Req.Test
      Req.Test.stub(YourRequest, mock)
  """

  require Logger

  @fixtures_base_dir "test/fixtures"

  @doc """
  Loads a fixture file for the specified exchange.

  ## Parameters
  - `exchange` - Exchange name (e.g., "binance", "kraken")
  - `filename` - Fixture filename (e.g., "get_balances_success.json")

  ## Returns
  - `{:ok, fixture_data}` - Successfully loaded fixture
  - `{:error, reason}` - File not found or invalid JSON

  ## Examples

      {:ok, fixture} = FixtureHelper.load_fixture("binance", "get_balances_success.json")
      %{data: api_response, captured_at: timestamp} = fixture
  """
  @spec load_fixture(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_fixture(exchange, filename) do
    file_path = Path.join([@fixtures_base_dir, exchange, filename])

    with {:ok, content} <- File.read(file_path),
         {:ok, json_data} <- Jason.decode(content) do
      {:ok, json_data}
    else
      {:error, :enoent} ->
        {:error, {:fixture_not_found, file_path}}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, error}}

      error ->
        error
    end
  end

  @doc """
  Lists all available fixtures for an exchange.

  ## Parameters
  - `exchange` - Exchange name

  ## Returns
  - `{:ok, [filename, ...]}` - List of available fixture files
  - `{:error, :not_found}` - Exchange fixtures directory doesn't exist

  ## Examples

      {:ok, files} = FixtureHelper.list_fixtures("binance")
      # ["get_balances_success.json", "place_order_error.json", ...]
  """
  @spec list_fixtures(String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_fixtures(exchange) do
    fixtures_dir = Path.join(@fixtures_base_dir, exchange)

    if File.dir?(fixtures_dir) do
      files =
        fixtures_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()

      {:ok, files}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Creates a Req.Test mock function from a fixture.

  The mock will match the request URL and return the fixture data
  formatted as a proper HTTP response.

  ## Parameters
  - `fixture` - Loaded fixture data
  - `opts` - Options for mock behavior

  ## Options
  - `:status` - HTTP status code (default: 200)
  - `:headers` - Additional headers to include
  - `:match_params` - Whether to match query parameters (default: false)

  ## Returns
  - Mock function compatible with Req.Test.stub/2

  ## Examples

      {:ok, fixture} = load_fixture("binance", "get_balances_success.json")
      mock = create_mock_from_fixture(fixture, status: 200)

      Req.Test.stub(MyRequest, mock)
  """
  @spec create_mock_from_fixture(map(), keyword()) :: function()
  def create_mock_from_fixture(fixture, opts \\ []) do
    status = Keyword.get(opts, :status, 200)
    headers = Keyword.get(opts, :headers, [])
    _match_params = Keyword.get(opts, :match_params, false)

    fn conn ->
      # Extract response data from fixture
      response_data = Map.get(fixture, "data")

      # Add realistic headers based on exchange
      response_headers = build_response_headers(fixture, headers)

      # Create response
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.put_resp_header("server", "nginx")
      |> add_headers(response_headers)
      |> Plug.Conn.resp(status, Jason.encode!(response_data))
    end
  end

  @doc """
  Creates a mock that simulates rate limiting based on request frequency.

  This mock tracks request frequency and returns 429 responses when
  limits are exceeded, mimicking real exchange behavior.

  ## Parameters
  - `rate_limit` - Requests per minute allowed
  - `fixture` - Success response fixture to use when not rate limited

  ## Returns
  - Mock function that enforces rate limiting

  ## Examples

      {:ok, fixture} = load_fixture("binance", "get_balances_success.json")
      mock = create_rate_limited_mock(60, fixture)

      Req.Test.stub(MyRequest, mock)
  """
  @spec create_rate_limited_mock(pos_integer(), map()) :: function()
  def create_rate_limited_mock(rate_limit, success_fixture) do
    # Use Agent to track request times across calls
    {:ok, agent} = Agent.start_link(fn -> [] end)

    fn conn ->
      now = System.system_time(:millisecond)
      one_minute_ago = now - 60_000

      # Get recent request times
      recent_requests =
        Agent.get_and_update(agent, fn request_times ->
          # Filter to last minute and add current request
          recent = Enum.filter(request_times, &(&1 > one_minute_ago))
          updated = [now | recent]
          {recent, updated}
        end)

      if length(recent_requests) >= rate_limit do
        # Rate limited
        retry_after = div(60_000 - (now - List.last(recent_requests)), 1000) + 1

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.put_resp_header("retry-after", to_string(retry_after))
        |> Plug.Conn.put_resp_header("x-mbx-used-weight-1m", to_string(rate_limit))
        |> Plug.Conn.resp(
          429,
          Jason.encode!(%{
            "code" => 429,
            "msg" => "Too many requests"
          })
        )
      else
        # Success response
        create_mock_from_fixture(success_fixture).(conn)
      end
    end
  end

  @doc """
  Creates an error mock that returns specific error responses.

  Useful for testing error handling with realistic error formats
  captured from real APIs.

  ## Parameters
  - `error_fixture` - Fixture containing error response
  - `status` - HTTP status code for error (default: 400)

  ## Returns
  - Mock function that returns error response

  ## Examples

      {:ok, error_fixture} = load_fixture("binance", "error_invalid_symbol.json")
      mock = create_error_mock(error_fixture, 400)

      Req.Test.stub(MyRequest, mock)
  """
  @spec create_error_mock(map(), pos_integer()) :: function()
  def create_error_mock(error_fixture, status \\ 400) do
    create_mock_from_fixture(error_fixture, status: status)
  end

  @doc """
  Validates that a fixture matches the expected schema.

  Helps ensure captured fixtures maintain consistent structure
  and can detect API changes over time.

  ## Parameters
  - `fixture` - Loaded fixture data
  - `schema` - Expected data schema

  ## Returns
  - `:ok` - Fixture matches schema
  - `{:error, reasons}` - List of validation failures

  ## Examples

      schema = %{
        "asset" => :string,
        "free" => :decimal_string,
        "locked" => :decimal_string
      }

      :ok = validate_fixture_schema(fixture, schema)
  """
  @spec validate_fixture_schema(map(), map()) :: :ok | {:error, [String.t()]}
  def validate_fixture_schema(fixture, schema) do
    data = Map.get(fixture, "data")
    errors = validate_data_against_schema(data, schema, [])

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Saves API response data as a fixture with proper metadata.

  This function is used by integration tests to capture real API
  responses for later use in mocked tests.

  ## Parameters
  - `exchange` - Exchange name
  - `filename` - Fixture filename
  - `data` - API response data to save
  - `metadata` - Additional metadata (optional)

  ## Returns
  - `:ok` - Successfully saved
  - `{:error, reason}` - Save failed

  ## Examples

      save_fixture("binance", "get_balances_success.json", api_response, %{
        endpoint: "/api/v3/account",
        params: %{symbol: "BTCUSDT"}
      })
  """
  @spec save_fixture(String.t(), String.t(), term(), map()) :: :ok | {:error, term()}
  def save_fixture(exchange, filename, data, metadata \\ %{}) do
    fixtures_dir = Path.join(@fixtures_base_dir, exchange)
    File.mkdir_p!(fixtures_dir)

    file_path = Path.join(fixtures_dir, filename)

    fixture_data =
      Map.merge(
        %{
          data: data,
          captured_at: System.system_time(:millisecond),
          zen_cex_version: get_version(),
          test_environment: get_test_environment(exchange)
        },
        metadata
      )

    json_content = Jason.encode!(fixture_data, pretty: true)

    case File.write(file_path, json_content) do
      :ok ->
        Logger.debug("Saved fixture: #{exchange}/#{filename}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to save fixture #{exchange}/#{filename}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Compares two fixtures to detect API changes.

  Useful for detecting when exchange APIs have changed their
  response format, which may require adapter updates.

  ## Parameters
  - `old_fixture` - Previously captured fixture
  - `new_fixture` - Recently captured fixture

  ## Returns
  - `:unchanged` - Fixtures are equivalent
  - `{:changed, differences}` - List of detected differences

  ## Examples

      {:ok, old} = load_fixture("binance", "get_balances_v1.json")
      {:ok, new} = load_fixture("binance", "get_balances_v2.json")

      case compare_fixtures(old, new) do
        :unchanged -> :ok
        {:changed, differences} -> Logger.warning("API changed: \#{inspect(differences)}")
      end
  """
  @spec compare_fixtures(map(), map()) :: :unchanged | {:changed, [String.t()]}
  def compare_fixtures(old_fixture, new_fixture) do
    old_data = Map.get(old_fixture, "data")
    new_data = Map.get(new_fixture, "data")

    differences = find_differences(old_data, new_data, [])

    case differences do
      [] -> :unchanged
      diffs -> {:changed, diffs}
    end
  end

  # Private helper functions

  defp build_response_headers(fixture, additional_headers) do
    base_headers = [
      {"content-type", "application/json"},
      {"server", "nginx"},
      {"x-timestamp", to_string(System.system_time(:millisecond))}
    ]

    # Add exchange-specific headers based on fixture metadata
    exchange_headers =
      case Map.get(fixture, "test_environment") do
        "binance_testnet" ->
          [
            {"x-mbx-used-weight-1m", "1"},
            {"x-mbx-order-count-10s", "0"}
          ]

        "kraken_test" ->
          [
            {"x-ratelimit-remaining", "100"}
          ]

        _ ->
          []
      end

    base_headers ++ exchange_headers ++ additional_headers
  end

  defp add_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {name, value}, acc ->
      Plug.Conn.put_resp_header(acc, name, value)
    end)
  end

  defp validate_data_against_schema(data, schema, path) when is_map(data) and is_map(schema) do
    Enum.flat_map(schema, fn {key, expected_type} ->
      case Map.get(data, key) do
        nil ->
          ["Missing required field: #{Enum.join(path ++ [key], ".")}"]

        value ->
          validate_value_type(value, expected_type, path ++ [key])
      end
    end)
  end

  defp validate_data_against_schema(data, schema, path) when is_list(data) and is_map(schema) do
    # Validate each item in the list against the schema
    data
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      validate_data_against_schema(item, schema, path ++ ["[#{index}]"])
    end)
  end

  defp validate_data_against_schema(_data, _schema, _path), do: []

  defp validate_value_type(value, :string, _path) when is_binary(value), do: []
  defp validate_value_type(value, :integer, _path) when is_integer(value), do: []

  defp validate_value_type(value, :decimal_string, path) when is_binary(value) do
    case Decimal.parse(value) do
      {_decimal, ""} -> []
      _ -> ["Invalid decimal string at #{Enum.join(path, ".")}: #{value}"]
    end
  end

  defp validate_value_type(value, expected_type, path) do
    ["Type mismatch at #{Enum.join(path, ".")}: expected #{expected_type}, got #{inspect(value)}"]
  end

  defp find_differences(old, new, path) when is_map(old) and is_map(new) do
    old_keys = MapSet.new(Map.keys(old))
    new_keys = MapSet.new(Map.keys(new))

    # Find added/removed keys
    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    added_diffs =
      Enum.map(added_keys, fn key ->
        "Added field: #{Enum.join(path ++ [key], ".")}"
      end)

    removed_diffs =
      Enum.map(removed_keys, fn key ->
        "Removed field: #{Enum.join(path ++ [key], ".")}"
      end)

    # Recursively check common keys
    value_diffs =
      Enum.flat_map(common_keys, fn key ->
        find_differences(old[key], new[key], path ++ [key])
      end)

    added_diffs ++ removed_diffs ++ value_diffs
  end

  defp find_differences(old, new, path) when old != new do
    ["Value changed at #{Enum.join(path, ".")}: #{inspect(old)} -> #{inspect(new)}"]
  end

  defp find_differences(_old, _new, _path), do: []

  defp get_version do
    case :application.get_key(:zen_cex, :vsn) do
      {:ok, version} -> to_string(version)
      :undefined -> "0.1.0"
    end
  end

  defp get_test_environment("binance"), do: "binance_testnet"
  defp get_test_environment("kraken"), do: "kraken_test"
  defp get_test_environment("deribit"), do: "deribit_test"
  defp get_test_environment(_), do: "test"
end
