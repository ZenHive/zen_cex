defmodule ZenCex.Core.ResponseParser do
  @moduledoc """
  Core response parsing utilities for exchange adapters.

  Provides common patterns for parsing HTTP responses, handling errors,
  and normalizing data formats. Exchange-specific parsers can use these
  utilities to reduce duplication while maintaining flexibility for
  exchange-specific formats.

  ## Features
  - HTTP status code to error atom mapping
  - JSON parsing with error handling
  - Response structure normalization
  - Rate limit header extraction
  - Error message standardization
  - HTML error page detection
  """

  require Logger

  # Common HTTP status to error atom mappings
  @http_status_errors %{
    400 => :bad_request,
    401 => :unauthorized,
    403 => :forbidden,
    404 => :not_found,
    429 => :rate_limited,
    500 => :internal_server_error,
    502 => :bad_gateway,
    503 => :service_unavailable
  }

  @doc """
  Maps HTTP status codes to standardized error atoms.

  ## Examples

      iex> map_http_status_to_error(401)
      :unauthorized

      iex> map_http_status_to_error(429)
      :rate_limited

      iex> map_http_status_to_error(999)
      {:http_error, 999}
  """
  @spec map_http_status_to_error(integer()) :: atom() | {:http_error, integer()}
  def map_http_status_to_error(status) when is_integer(status) do
    Map.get(@http_status_errors, status, {:http_error, status})
  end

  @doc """
  Parses JSON response body with error handling.

  ## Examples

      iex> parse_json_body("{\\"key\\": \\"value\\"}")
      {:ok, %{"key" => "value"}}

      iex> parse_json_body("invalid json")
      {:error, :invalid_json}

      iex> parse_json_body("")
      {:error, :empty_response}
  """
  @spec parse_json_body(binary()) :: {:ok, map() | list()} | {:error, atom()}
  def parse_json_body(""), do: {:error, :empty_response}

  def parse_json_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse_json_body(_), do: {:error, :invalid_response}

  @doc """
  Normalizes response structure to {:ok, data} or {:error, reason}.

  Handles various response formats:
  - Successful JSON responses
  - Error responses with codes/messages
  - HTML error pages
  - Empty responses

  ## Examples

      iex> normalize_response(%{status: 200, body: "{\\"data\\": \\"value\\"}"})
      {:ok, %{"data" => "value"}}

      iex> normalize_response(%{status: 401, body: "{\\"msg\\": \\"Unauthorized\\"}"})
      {:error, :unauthorized}
  """
  @spec normalize_response(map()) :: {:ok, term()} | {:error, term()}
  def normalize_response(%{status: status, body: body}) when status >= 200 and status < 300 do
    parse_json_body(body)
  end

  def normalize_response(%{status: status, body: body}) do
    case parse_json_body(body) do
      {:ok, error_data} when is_map(error_data) ->
        # Let exchange-specific parser handle error details
        {:error, error_data}

      {:error, :invalid_json} ->
        # Might be HTML error page
        parse_html_error(body, status)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def normalize_response(_), do: {:error, :invalid_response}

  @doc """
  Extracts rate limit information from response headers.

  Common rate limit headers:
  - `x-ratelimit-remaining`
  - `x-ratelimit-limit`
  - `x-ratelimit-reset`
  - Exchange-specific headers (e.g., `x-mbx-used-weight`)

  ## Examples

      iex> headers = [{"x-ratelimit-remaining", "99"}, {"x-ratelimit-limit", "100"}]
      iex> extract_rate_limit_info(headers)
      %{remaining: 99, limit: 100}
  """
  @spec extract_rate_limit_info(list()) :: map()
  def extract_rate_limit_info(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, fn
      {"x-ratelimit-remaining", value}, acc ->
        Map.put(acc, :remaining, to_integer(value))

      {"x-ratelimit-limit", value}, acc ->
        Map.put(acc, :limit, to_integer(value))

      {"x-ratelimit-reset", value}, acc ->
        Map.put(acc, :reset, to_integer(value))

      {"x-mbx-used-weight", value}, acc ->
        Map.put(acc, :weight_used, to_integer(value))

      {"x-mbx-used-weight-1m", value}, acc ->
        Map.put(acc, :weight_used_1m, to_integer(value))

      _, acc ->
        acc
    end)
  end

  def extract_rate_limit_info(_), do: %{}

  @doc """
  Standardizes error messages across exchanges.

  Maps common error patterns to consistent error atoms:
  - "insufficient balance" → :insufficient_balance
  - "invalid symbol" → :invalid_symbol
  - "unauthorized" → :unauthorized
  - etc.

  ## Examples

      iex> standardize_error_message("Account has insufficient balance")
      :insufficient_balance

      iex> standardize_error_message("Invalid symbol BTCUSDT")
      :invalid_symbol

      iex> standardize_error_message("Unknown error occurred")
      {:exchange_error, "Unknown error occurred"}
  """
  @spec standardize_error_message(binary()) :: atom() | {:exchange_error, binary()}
  def standardize_error_message(message) when is_binary(message) do
    lower_message = String.downcase(message)

    cond do
      String.contains?(lower_message, "insufficient") ->
        :insufficient_balance

      String.contains?(lower_message, ["invalid symbol", "symbol is invalid"]) ->
        :invalid_symbol

      String.contains?(lower_message, ["unauthorized", "authentication"]) ->
        :unauthorized

      String.contains?(lower_message, "rate limit") ->
        :rate_limited

      String.contains?(lower_message, "order not found") ->
        :order_not_found

      String.contains?(lower_message, "not found") ->
        :not_found

      String.contains?(lower_message, "invalid quantity") ->
        :invalid_quantity

      String.contains?(lower_message, "invalid price") ->
        :invalid_price

      String.contains?(lower_message, "signature") ->
        :signature_not_valid

      true ->
        {:exchange_error, message}
    end
  end

  def standardize_error_message(_), do: :unknown_error

  @doc """
  Parses HTML error pages and extracts meaningful error information.

  Detects common CDN/WAF error pages and HTTP status codes in HTML.
  The status parameter is optional - if nil, attempts to detect from HTML content.

  ## Examples

      iex> parse_html_error("<html>403 Forbidden</html>", 403)
      {:error, {:html_error, "403 Forbidden - Access denied by server"}}

      iex> parse_html_error("<html>CloudFlare protection</html>", 503)
      {:error, {:cdn_error, "CloudFlare protection triggered"}}
      
      iex> parse_html_error("<html>403 Forbidden</html>", nil)
      {:error, {:html_error, "403 Forbidden - Access denied by server"}}
  """
  @spec parse_html_error(binary(), integer() | nil) :: {:error, term()}
  def parse_html_error(html, status \\ nil)

  def parse_html_error(html, status) when is_binary(html) do
    cond do
      String.contains?(html, "Request blocked") ->
        {:error, {:waf_blocked, "Request blocked by WAF"}}

      String.contains?(html, ["CloudFlare", "cloudflare"]) ->
        {:error, {:cdn_error, "CloudFlare protection triggered"}}

      String.contains?(html, ["DOCTYPE", "<html", "<HTML"]) ->
        error_msg = extract_html_error_message(html, status)
        {:error, {:html_error, error_msg}}

      true ->
        if status do
          {:error, map_http_status_to_error(status)}
        else
          {:error, :unknown_error}
        end
    end
  end

  def parse_html_error(_, status) do
    if status do
      {:error, map_http_status_to_error(status)}
    else
      {:error, :unknown_error}
    end
  end

  @doc """
  Validates that a response contains expected fields.

  Useful for ensuring responses match expected format before parsing.

  ## Examples

      iex> validate_required_fields(%{"symbol" => "BTC", "price" => "50000"}, ["symbol", "price"])
      :ok

      iex> validate_required_fields(%{"symbol" => "BTC"}, ["symbol", "price"])
      {:error, {:missing_fields, ["price"]}}
  """
  @spec validate_required_fields(map(), list(String.t())) :: :ok | {:error, {:missing_fields, list()}}
  def validate_required_fields(response, required_fields) when is_map(response) and is_list(required_fields) do
    missing_fields = Enum.reject(required_fields, &Map.has_key?(response, &1))

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  def validate_required_fields(_, _), do: {:error, :invalid_format}

  @doc """
  Logs debug information for error responses.

  Useful for debugging API issues without exposing sensitive data in production.

  ## Examples

      iex> log_error_response(%{"code" => -1121, "msg" => "Invalid symbol"}, "Binance")
      :ok
  """
  @spec log_error_response(term(), String.t()) :: :ok
  def log_error_response(response, exchange_name \\ "Exchange") do
    Logger.debug("#{exchange_name} error response: #{inspect(response, pretty: true)}")
    :ok
  end

  # Private helper functions

  defp extract_html_error_message(html, status) do
    cond do
      String.contains?(html, "403 Forbidden") ->
        "403 Forbidden - Access denied by server"

      String.contains?(html, "429 Too Many Requests") ->
        "429 Too Many Requests - Rate limit exceeded"

      String.contains?(html, "502 Bad Gateway") ->
        "502 Bad Gateway - Server temporarily unavailable"

      String.contains?(html, "503 Service Unavailable") ->
        "503 Service Unavailable - Server overloaded or under maintenance"

      is_integer(status) and status == 404 ->
        "404 Not Found - Endpoint not found"

      is_integer(status) and status >= 500 ->
        "Server error - #{status}"

      is_integer(status) and status >= 400 ->
        "Client error - #{status}"

      true ->
        "Server returned HTML error page instead of JSON response"
    end
  end

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(_), do: 0
end
