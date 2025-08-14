defmodule ZenCex.HTTP do
  @moduledoc """
  HTTP client for exchange REST APIs using REQ with exponential backoff.

  Provides pure functions for building requests, handling responses,
  and managing exchange-specific configurations.
  """

  alias ZenCex.{RateLimit, ReqHelpers}
  require Logger

  @doc """
  Returns the base URL for the specified exchange.
  """
  @spec exchange_url(atom()) :: String.t()
  def exchange_url(:binance), do: "https://api.binance.com"
  def exchange_url(:binance_futures), do: "https://fapi.binance.com"
  def exchange_url(:kraken), do: "https://api.kraken.com"
  def exchange_url(:deribit), do: "https://www.deribit.com"
  def exchange_url(:deribit_test), do: "https://test.deribit.com"

  def exchange_url(exchange) do
    raise ArgumentError, "Unknown exchange: #{inspect(exchange)}"
  end

  @doc """
  Returns the timeout in milliseconds for the specified operation type.
  """
  @spec operation_timeout(atom()) :: non_neg_integer()
  def operation_timeout(:trading), do: 2_000
  def operation_timeout(:market_data), do: 5_000
  def operation_timeout(:historical), do: 30_000
  def operation_timeout(_), do: 5_000

  @doc """
  Creates a base REQ request configured for the specified exchange.

  Includes:
  - Exponential backoff with jitter
  - Operation-specific timeouts
  - Request/response middleware
  - Compression support

  ## Weight Override Example

  For endpoints with custom rate limit weights:

      request = base_request(:binance)
      |> ReqHelpers.put_private(:rate_limit_weight, 10)
      |> Req.get("/api/v3/order")
  """
  @spec base_request(atom(), atom()) :: Req.Request.t()
  def base_request(exchange, operation_type \\ :market_data) do
    timeout = operation_timeout(operation_type)

    request =
      Req.new(
        base_url: exchange_url(exchange),
        finch: ZenCex.Finch,
        retry: :safe_transient,
        retry_delay: &exponential_backoff/1,
        max_retries: 3,
        compressed: true,
        receive_timeout: timeout,
        pool_timeout: 1_000
      )

    # Store exchange in both options and private for middleware
    # Also set default rate limit weight
    request
    |> then(fn req ->
      %{req | options: Map.put(req.options, :exchange, exchange)}
    end)
    |> ReqHelpers.merge_private(%{
      exchange: exchange,
      rate_limit_weight: 1
    })
    |> Req.Request.prepend_request_steps(
      inject_timestamp: &inject_timestamp/1,
      check_rate_limit: &check_rate_limit/1,
      add_request_id: &add_request_id/1
    )
    |> Req.Request.append_response_steps(
      handle_rate_limit: &handle_rate_limit_response/1,
      extract_weight: &extract_weight/1
    )
  end

  @doc """
  Calculates exponential backoff delay with jitter.

  Formula: min(2^n * 1000, 60000) + random(0-500)ms
  """
  @spec exponential_backoff(non_neg_integer()) :: non_neg_integer()
  def exponential_backoff(attempt) do
    base_ms = min(:math.pow(2, min(attempt, 10)) * 1000, 60_000)
    jitter_ms = :rand.uniform(500)

    trunc(min(base_ms + jitter_ms, 60_000))
  end

  @doc """
  Injects current timestamp into request headers.
  """
  @spec inject_timestamp(Req.Request.t()) :: Req.Request.t()
  def inject_timestamp(request) do
    timestamp = System.system_time(:millisecond)

    request
    |> Req.Request.put_header("x-timestamp", to_string(timestamp))
    |> ReqHelpers.put_private(:timestamp, timestamp)
  end

  @doc """
  Checks rate limits before sending request.

  Integrates with Exchange.RateLimit module to enforce per-exchange limits.
  """
  @spec check_rate_limit(Req.Request.t()) :: Req.Request.t()
  def check_rate_limit(request) do
    # Check private first, fall back to options for exchange
    exchange = ReqHelpers.get_private(request, :exchange) || request.options[:exchange]

    # Get endpoint from URL path
    endpoint =
      case request.url do
        %URI{path: nil} -> "/"
        %URI{path: path} -> path
      end

    # Get weight from private field (default is 1)
    weight = ReqHelpers.get_private(request, :rate_limit_weight, 1)

    case RateLimit.check_and_increment(exchange, endpoint, weight) do
      :ok ->
        request

      {:error, :rate_limited} ->
        # Halt the request pipeline on rate limit
        %{request | halted: true}
        |> ReqHelpers.put_private(:error, {:rate_limit_exceeded, exchange})
    end
  end

  @doc """
  Checks rate limit with explicit count (for testing).

  ## Per-Request Weight Configuration

  To set custom weights for specific endpoints:

      # High-weight endpoint (e.g., placing orders)
      request
      |> ReqHelpers.put_private(:rate_limit_weight, 50)
      |> Req.post("/api/v3/order")

      # Low-weight endpoint (e.g., server time)
      request
      |> ReqHelpers.put_private(:rate_limit_weight, 1)
      |> Req.get("/api/v3/time")
  """
  @spec check_rate_limit_with_count(Req.Request.t(), non_neg_integer()) ::
          {:ok, Req.Request.t()} | {:error, {:rate_limit_exceeded, atom()}}
  def check_rate_limit_with_count(request, count) do
    exchange = request.options[:exchange]

    limit =
      case exchange do
        :binance -> 1200
        :binance_futures -> 2400
        :kraken -> 15
        :deribit -> 20
        _ -> 1000
      end

    if count > limit do
      {:error, {:rate_limit_exceeded, exchange}}
    else
      {:ok, request}
    end
  end

  @doc """
  Adds unique request ID for tracing.
  """
  @spec add_request_id(Req.Request.t()) :: Req.Request.t()
  def add_request_id(request) do
    exchange = request.options[:exchange] || :unknown
    timestamp = System.system_time(:millisecond)
    unique = System.unique_integer([:positive])

    request_id = "#{exchange}-#{timestamp}-#{unique}"

    request
    |> Req.Request.put_header("x-request-id", request_id)
    |> ReqHelpers.put_private(:request_id, request_id)
  end

  @doc """
  Handles 429 rate limit responses and extracts Retry-After header.

  Checks for HTTP 429 status and respects the Retry-After header by:
  - Storing the retry delay in request private data
  - Logging the rate limit event with retry information
  - Allowing Req's retry mechanism to handle the actual retry
  """
  @spec handle_rate_limit_response({Req.Request.t(), Req.Response.t() | map()}) ::
          {Req.Request.t(), Req.Response.t() | map()}
  def handle_rate_limit_response({request, response} = req_resp) do
    status = Map.get(response, :status)

    if status == 429 do
      headers = Map.get(response, :headers, [])
      retry_after = extract_retry_after(headers)
      exchange = request.options[:exchange] || :unknown

      Logger.warning(
        "[#{exchange}] Rate limited (429). Retry after: #{retry_after}s. " <>
          "Request: #{(request.url && request.url.path) || "unknown"}"
      )

      # Store retry information in response private data for telemetry
      updated_response =
        case response do
          %Req.Response{} = r ->
            %{r | private: Map.put(r.private || %{}, :retry_after, retry_after)}

          %{} = m ->
            Map.put(m, :private, Map.put(m[:private] || %{}, :retry_after, retry_after))
        end

      # Emit telemetry event for monitoring
      :telemetry.execute(
        [:zen_cex, :exchange, :http, :rate_limited],
        %{retry_after: retry_after},
        %{exchange: exchange, status: 429}
      )

      {request, updated_response}
    else
      req_resp
    end
  end

  defp extract_retry_after(headers) when is_list(headers) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == "retry-after" end)
    |> case do
      {_, value} when is_binary(value) ->
        # Try to parse as integer (seconds)
        case Integer.parse(value) do
          {seconds, _} -> seconds
          # Default to 60 seconds if parsing fails
          _ -> 60
        end

      _ ->
        # Default retry after 60 seconds
        60
    end
  end

  defp extract_retry_after(headers) when is_map(headers) do
    headers
    |> Map.get("retry-after", headers["Retry-After"])
    |> case do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {seconds, _} -> seconds
          _ -> 60
        end

      _ ->
        60
    end
  end

  defp extract_retry_after(_), do: 60

  @doc """
  Extracts rate limit information from response headers.

  Handles both Req.Response structs (production) and plain maps (testing).
  Returns the proper Req response step contract: `{:ok, {request, response}}`.
  """
  @spec extract_weight({any(), Req.Response.t() | map()}) ::
          {any(), Req.Response.t() | map()}
  def extract_weight({request, response}) do
    {headers, current_private} = extract_response_data(response)

    # Normalize headers to a map for consistent access
    headers_map = normalize_headers(headers)

    updated_private =
      current_private
      |> extract_binance_weight(headers_map)
      |> extract_kraken_limits(headers_map)

    # Reconcile server-reported weights with local rate limiter
    reconcile_rate_limits(request, headers_map)

    updated_response = update_response_private(response, updated_private)

    # Return the proper Req step contract with both request and response
    {request, updated_response}
  end

  defp reconcile_rate_limits(%{private: %{exchange: exchange}} = _request, headers)
       when exchange in [:binance, :binance_futures] do
    alias ZenCex.RateLimit
    RateLimit.update_from_headers(exchange, headers)
  end

  defp reconcile_rate_limits(_, _), do: :ok

  # Normalizes headers to a map with lowercase keys for consistent access
  # Handles both list of tuples (from Req.Response) and maps (from tests)
  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(key), value)
    end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    # Already a map, normalize keys to lowercase for consistency
    headers
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(to_string(key)), value)
    end)
  end

  defp normalize_headers(_), do: %{}

  defp extract_response_data(%Req.Response{headers: h, private: p}) do
    {h || %{}, p || %{}}
  end

  defp extract_response_data(%{headers: h} = response) do
    {h || %{}, response[:private] || %{}}
  end

  defp extract_response_data(_) do
    {%{}, %{}}
  end

  defp update_response_private(%Req.Response{} = r, private) do
    %{r | private: private}
  end

  defp update_response_private(%{} = m, private) do
    Map.put(m, :private, private)
  end

  defp extract_binance_weight(private, headers) do
    private
    |> maybe_put_header_int(headers, "x-mbx-used-weight-1m", :rate_limit_weight)
    |> maybe_put_header_int(headers, "x-mbx-order-count-1m", :order_count)
  end

  defp extract_kraken_limits(private, headers) do
    private
    |> maybe_put_header_int(headers, "x-ratelimit-remaining", :rate_limit_remaining)
    |> maybe_put_header_int(headers, "x-ratelimit-limit", :rate_limit_limit)
  end

  defp maybe_put_header_int(private, headers, header_name, key) do
    # Headers are normalized to lowercase keys
    normalized_name = String.downcase(header_name)

    case Map.get(headers, normalized_name) do
      [value | _] when is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> Map.put(private, key, int)
          _ -> private
        end

      value when is_binary(value) ->
        # Handle case where value is a single string (from test maps)
        case Integer.parse(value) do
          {int, _} -> Map.put(private, key, int)
          _ -> private
        end

      _ ->
        private
    end
  end

  @doc """
  Parses HTTP response based on expected format.

  Handles both pre-decoded JSON (when Req auto-decodes) and raw binary responses.
  Use `:json` format when expecting JSON data, `:raw` for binary/text responses.
  """
  @spec parse_response(map(), :json | :raw) ::
          {:ok, any()}
          | {:error, {:http_error, integer(), any()}}
          | {:error, {:parse_error, any()}}
  def parse_response(%{status: status, body: body}, format) when status >= 200 and status < 300 do
    case format do
      :json ->
        # Handle both pre-decoded maps and raw JSON strings
        cond do
          is_map(body) or is_list(body) ->
            # Already decoded by Req
            {:ok, body}

          is_binary(body) ->
            # Need to decode
            case Jason.decode(body) do
              {:ok, parsed} -> {:ok, parsed}
              {:error, error} -> {:error, {:parse_error, error}}
            end

          true ->
            {:error, {:parse_error, "Unexpected body type: #{inspect(body)}"}}
        end

      :raw ->
        {:ok, body}
    end
  end

  def parse_response(%{status: status, body: body}, :json) do
    # Try to decode error response if it's JSON
    error_body =
      cond do
        is_map(body) or is_list(body) ->
          body

        is_binary(body) ->
          case Jason.decode(body) do
            {:ok, parsed} -> parsed
            _ -> body
          end

        true ->
          body
      end

    {:error, {:http_error, status, error_body}}
  end

  def parse_response(%{status: status, body: body}, _format) do
    {:error, {:http_error, status, body}}
  end

  @doc """
  Builds URL query string from parameters map.
  """
  @spec build_query_string(map()) :: String.t()
  def build_query_string(params) when params == %{}, do: ""

  def build_query_string(params) do
    Enum.map_join(params, "&", fn {key, value} ->
      "#{key}=#{URI.encode_www_form(to_string(value))}"
    end)
  end
end
