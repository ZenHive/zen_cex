defmodule ZenCex.Adapters.Bybit.Parser do
  @moduledoc """
  Response parser for Bybit V5 API.

  Handles Bybit's unified response structure with retCode/retMsg/result format.
  Leverages Core.ResponseParser for common parsing patterns while handling
  Bybit-specific response formats and error codes.

  ## Response Structure
  All Bybit V5 API responses follow this structure:
  ```json
  {
    "retCode": 0,        // 0 = success, non-zero = error
    "retMsg": "OK",      // Human-readable message
    "result": {...},     // Response data (null on error)
    "retExtInfo": {},    // Extended info (usually empty)
    "time": 1672211736359 // Server timestamp (ms)
  }
  ```

  ## Error Codes
  - 10001-10999: Authentication/signature errors
  - 11000-11999: Order-related errors
  - 12000-12999: Position-related errors
  - 20000-29999: Business logic errors
  - 30000-39999: API-specific errors
  - 110000+: System and rate limit errors
  """

  alias ZenCex.Core.ResponseParser

  require Logger

  # Bybit-specific error code mappings
  @error_code_atoms %{
    # Authentication errors (10xxx)
    10_001 => :invalid_request_params,
    10_002 => :invalid_api_key,
    10_003 => :invalid_signature,
    10_004 => :signature_not_valid,
    10_005 => :permission_denied,
    10_006 => :rate_limited,
    10_007 => :api_key_expired,
    10_008 => :invalid_recv_window,
    10_009 => :invalid_timestamp,
    10_010 => :ip_not_whitelisted,

    # Order errors (110xxx)
    110_001 => :order_not_found,
    110_003 => :order_already_canceled,
    110_004 => :insufficient_balance,
    110_005 => :invalid_order_qty,
    110_007 => :invalid_order_price,
    110_012 => :invalid_symbol,
    110_013 => :invalid_order_type,
    110_014 => :invalid_order_side,
    110_017 => :duplicate_order_id,
    110_025 => :position_not_found,
    110_043 => :order_would_trigger_immediately,

    # Business errors (170xxx)
    170_131 => :insufficient_balance,

    # System errors (10000+)
    10_016 => :server_error,
    10_018 => :too_many_requests,
    10_027 => :timestamp_out_of_range,
    20_001 => :order_not_exists,
    30_024 => :account_not_unified,

    # Rate limit specific
    130_006 => :rate_limit_exceeded,
    140_003 => :request_frequency_exceeded
  }

  @doc """
  Parses a Bybit API response into a standardized format.

  Returns `{:ok, result}` for successful responses or `{:error, reason}` for errors.

  ## Examples

      iex> parse(%{status: 200, body: ~s({"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT"}})})
      {:ok, %{"symbol" => "BTCUSDT"}}

      iex> parse(%{status: 200, body: ~s({"retCode":10006,"retMsg":"Too many visits!"})})
      {:error, :rate_limited}
  """
  @spec parse(map()) :: {:ok, term()} | {:error, term()}
  def parse(%{status: status, body: body} = response) when is_binary(body) do
    case ResponseParser.parse_json_body(body) do
      {:ok, parsed} ->
        handle_bybit_response(parsed, status, response)

      {:error, :invalid_json} ->
        ResponseParser.parse_html_error(body, status)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Handle case where Req has already decoded the JSON to a map
  def parse(%{status: status, body: body} = response) when is_map(body) do
    handle_bybit_response(body, status, response)
  end

  # Handle direct map response (from successful requests)
  def parse(%{"retCode" => _} = body) do
    # This is a direct Bybit response body
    handle_bybit_response(body, 200, %{})
  end

  def parse(%{status: status}) do
    # No body or non-binary body
    {:error, ResponseParser.map_http_status_to_error(status)}
  end

  def parse(_), do: {:error, :invalid_response}

  @doc """
  Extracts rate limit information from Bybit response headers and body.

  Bybit includes rate limit info in the response body's retExtInfo field
  and sometimes in headers.
  """
  @spec extract_rate_limits(map()) :: map()
  def extract_rate_limits(%{headers: headers, body: body}) when is_list(headers) do
    header_limits = ResponseParser.extract_rate_limit_info(headers)

    body_limits =
      case ResponseParser.parse_json_body(body) do
        {:ok, %{"retExtInfo" => ext_info}} when is_map(ext_info) ->
          parse_ext_info_limits(ext_info)

        _ ->
          %{}
      end

    Map.merge(header_limits, body_limits)
  end

  def extract_rate_limits(_), do: %{}

  # Private functions

  defp handle_bybit_response(%{"retCode" => 0, "result" => result}, _status, _response) do
    {:ok, result}
  end

  defp handle_bybit_response(%{"retCode" => 0} = data, _status, _response) do
    # Success but no result field (some endpoints return data at root level)
    {:ok, Map.drop(data, ["retCode", "retMsg", "time", "retExtInfo"])}
  end

  defp handle_bybit_response(%{"retCode" => code, "retMsg" => msg}, _status, _response) when is_integer(code) do
    error_atom = Map.get(@error_code_atoms, code)

    if error_atom do
      # Preserve both the atom and original message for debugging context
      # This allows callers to match on the atom while still having access to the detailed message
      {:error, {error_atom, msg}}
    else
      # Unknown error code - use standardized error message parsing
      case ResponseParser.standardize_error_message(msg) do
        {:exchange_error, _} -> {:error, {code, msg}}
        atom -> {:error, atom}
      end
    end
  end

  defp handle_bybit_response(%{"retCode" => code, "retMsg" => msg}, _status, _response) do
    # Non-integer retCode (shouldn't happen but handle gracefully)
    Logger.warning("Bybit returned non-integer retCode: #{inspect(code)}")
    {:error, {code, msg}}
  end

  defp handle_bybit_response(data, status, _response) when is_map(data) do
    # Response doesn't have expected Bybit structure
    Logger.debug("Bybit response missing retCode/retMsg structure: #{inspect(data)}")
    ResponseParser.normalize_response(%{status: status, body: Jason.encode!(data)})
  end

  defp handle_bybit_response(_, status, _response) do
    {:error, ResponseParser.map_http_status_to_error(status)}
  end

  defp parse_ext_info_limits(ext_info) do
    Enum.reduce(ext_info, %{}, fn
      {"rateLimit", value}, acc when is_integer(value) ->
        Map.put(acc, :rate_limit, value)

      {"rateLimitApi", value}, acc when is_binary(value) ->
        Map.put(acc, :rate_limit_api, value)

      {"rateLimitStatus", value}, acc when is_binary(value) ->
        Map.put(acc, :rate_limit_status, value)

      _, acc ->
        acc
    end)
  end

  # Specialized parsers for common endpoints

  @doc """
  Parses unified trading API responses.
  This is an alias for the main parse/1 function used by generated endpoints.
  """
  @spec parse_unified_response(map() | binary()) :: {:ok, term()} | {:error, term()}
  def parse_unified_response(response), do: parse(response)

  @doc """
  Parses server time response body directly.

  ## Examples

      iex> parse_server_time(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"timeSecond" => "1672211736", "timeNano" => "1672211736359000000"}})
      {:ok, %{"timeSecond" => "1672211736", "timeNano" => "1672211736359000000"}}
  """
  @spec parse_server_time(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_server_time(body) when is_map(body) do
    # Body is already decoded by Req
    handle_bybit_response(body, 200, %{})
  end

  def parse_server_time(body) when is_binary(body) do
    # If still a string, decode it first
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses error response body directly.
  """
  @spec parse_error(map() | binary()) :: {:error, term()}
  def parse_error(%{"retCode" => _} = body) do
    # Direct Bybit response body
    case handle_bybit_response(body, 400, %{}) do
      {:ok, _} -> {:error, :unexpected_success}
      error -> error
    end
  end

  def parse_error(body) when is_map(body) do
    # For errors, we expect a Bybit error structure
    case handle_bybit_response(body, 400, %{}) do
      {:ok, _} -> {:error, :unexpected_success}
      error -> error
    end
  end

  def parse_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_error(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses announcements response body directly.

  ## Examples

      iex> parse_announcements(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"list" => [...]}})
      {:ok, %{"list" => [...]}}
  """
  @spec parse_announcements(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_announcements(body) when is_map(body) do
    # Body is already decoded by Req
    handle_bybit_response(body, 200, %{})
  end

  def parse_announcements(body) when is_binary(body) do
    # If still a string, decode it first
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses wallet balance response.
  """
  @spec parse_wallet_balance(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_wallet_balance(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_wallet_balance(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses order response (place, cancel, get).
  """
  @spec parse_order(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_order(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_order(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses multiple orders response.
  """
  @spec parse_orders(map() | binary()) :: {:ok, list()} | {:error, term()}
  def parse_orders(body) when is_map(body) do
    case handle_bybit_response(body, 200, %{}) do
      {:ok, result} when is_map(result) ->
        # Extract list from result (handle both direct list and nested structure)
        orders = Map.get(result, "list", result)
        {:ok, orders}

      {:ok, result} when is_list(result) ->
        {:ok, result}

      error ->
        error
    end
  end

  def parse_orders(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_orders(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses batch cancel response.
  """
  @spec parse_batch_cancel(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_batch_cancel(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_batch_cancel(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses positions response.
  """
  @spec parse_positions(map() | binary()) :: {:ok, list()} | {:error, term()}
  def parse_positions(body) when is_map(body) do
    case handle_bybit_response(body, 200, %{}) do
      {:ok, result} when is_map(result) ->
        # Extract list from result
        positions = Map.get(result, "list", [])
        {:ok, positions}

      {:ok, result} when is_list(result) ->
        {:ok, result}

      error ->
        error
    end
  end

  def parse_positions(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_positions(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses trades/executions response.
  """
  @spec parse_trades(map() | binary()) :: {:ok, list()} | {:error, term()}
  def parse_trades(body) when is_map(body) do
    case handle_bybit_response(body, 200, %{}) do
      {:ok, result} when is_map(result) ->
        # Extract list from result
        trades = Map.get(result, "list", [])
        {:ok, trades}

      {:ok, result} when is_list(result) ->
        {:ok, result}

      error ->
        error
    end
  end

  def parse_trades(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_trades(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses generic response (for operations that don't need special handling).
  """
  @spec parse_generic(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_generic(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_generic(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses market data API responses.

  Market data responses can be:
  - Simple result for single items (ticker, instrument info)
  - List-based result for collections (klines, trades, order book)
  - Paginated results with nextPageCursor

  ## Examples

      iex> parse_market_data_response(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"list" => [...]}})
      {:ok, %{"list" => [...]}}
      
      iex> parse_market_data_response(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"symbol" => "BTCUSDT"}})
      {:ok, %{"symbol" => "BTCUSDT"}}
  """
  @spec parse_market_data_response(map() | binary()) :: {:ok, term()} | {:error, term()}
  def parse_market_data_response(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_market_data_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end
end
