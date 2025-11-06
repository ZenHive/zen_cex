defmodule ZenCex.Adapters.Deribit.Parser do
  @moduledoc """
  Response parser for Deribit API (JSON-RPC 2.0).

  Handles Deribit's JSON-RPC response structure and normalizes to zen_cex format.
  Follows pure Elixir error pass-through philosophy - all errors are returned
  as `{:error, raw_response}` with original exchange data preserved.

  ## Response Structure
  All Deribit API responses follow JSON-RPC 2.0 structure:
  ```json
  {
    "jsonrpc": "2.0",
    "id": 123,
    "result": {...}     // Success response data
  }
  ```

  Or for errors:
  ```json
  {
    "jsonrpc": "2.0",
    "id": 123,
    "error": {
      "code": -32602,
      "message": "Invalid params"
    }
  }
  ```

  ## Normalization
  The parser applies minimal transformation:
  - **Keys**: Converted to snake_case atoms (e.g., `"instrumentName"` → `:instrument_name`)
  - **Values**: Kept as-is from API (floats for prices, integers for timestamps)
  - **Enums**: Status/direction/type values converted to lowercase atoms (e.g., `"BUY"` → `:buy`)

  ## Error Handling
  All errors are returned unchanged as `{:error, raw_response}` preserving
  the complete JSON-RPC error structure.
  """

  import ZenCex.ParserMacros

  @doc """
  Parses a Deribit JSON-RPC response extracting the result field.

  Handles both direct API responses (with "result" key) and pre-extracted data.

  ## Examples

      # Direct JSON-RPC response
      iex> parse_generic(%{"result" => %{"instrument_name" => "BTC-PERPETUAL"}})
      {:ok, %{instrument_name: "BTC-PERPETUAL"}}

      # Pre-extracted data (from subscription)
      iex> parse_generic(%{"instrument_name" => "BTC-PERPETUAL"})
      {:ok, %{instrument_name: "BTC-PERPETUAL"}}

      # Error response
      iex> parse_generic(%{"error" => %{"code" => -32602, "message" => "Invalid params"}})
      {:error, %{error: %{code: -32602, message: "Invalid params"}}}
  """
  @spec parse_generic(map()) :: {:ok, map()} | {:error, term()}
  def parse_generic(%{"error" => _error} = response) do
    {:error, normalize_keys(response)}
  end

  def parse_generic(%{"result" => result}) when is_map(result) do
    {:ok, normalize_keys(result)}
  end

  def parse_generic(%{"result" => result}) when is_list(result) do
    {:ok, Enum.map(result, &normalize_keys/1)}
  end

  def parse_generic(%{"result" => result}) do
    {:ok, result}
  end

  def parse_generic(data) when is_map(data) do
    {:ok, normalize_keys(data)}
  end

  def parse_generic(data) when is_list(data) do
    {:ok, Enum.map(data, &normalize_keys/1)}
  end

  def parse_generic(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit order response.

  Handles both direct order responses (from buy/sell/cancel) and order lists.

  ## Examples

      # Single order from buy/sell
      response = %{
        "result" => %{
          "order" => %{
            "order_id" => "ETH-349253",
            "order_state" => "open",
            "direction" => "buy",
            "price" => 9000,
            "amount" => 100,
            "instrument_name" => "BTC-PERPETUAL"
          },
          "trades" => []
        }
      }
      {:ok, parsed} = parse_order(response)

      # Order from cancel response (no "order" wrapper)
      response = %{
        "result" => %{
          "order_id" => "ETH-349253",
          "order_state" => "cancelled",
          "direction" => "buy"
        }
      }
      {:ok, parsed} = parse_order(response)
  """
  @spec parse_order(map()) :: {:ok, map()} | {:error, term()}
  def parse_order(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_order(%{"result" => %{"order" => order}} = _response) when is_map(order) do
    # buy/sell response with order wrapper
    normalized = normalize_order(order)
    {:ok, normalized}
  end

  def parse_order(%{"result" => result}) when is_map(result) do
    # cancel response or get_order_state (no order wrapper)
    normalized = normalize_order(result)
    {:ok, normalized}
  end

  def parse_order(order) when is_map(order) do
    # Pre-extracted order data
    normalized = normalize_order(order)
    {:ok, normalized}
  end

  def parse_order(_), do: {:error, :invalid_format}

  @doc """
  Parses a list of Deribit orders.

  Used by get_open_orders, get_order_history, etc.

  ## Examples

      response = %{
        "result" => [
          %{
            "order_id" => "ETH-1",
            "order_state" => "open",
            "direction" => "buy"
          },
          %{
            "order_id" => "ETH-2",
            "order_state" => "filled",
            "direction" => "sell"
          }
        ]
      }
      {:ok, orders} = parse_orders(response)
  """
  @spec parse_orders(map() | list()) :: {:ok, list(map())} | {:error, term()}
  def parse_orders(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_orders(%{"result" => orders}) when is_list(orders) do
    normalized = Enum.map(orders, &normalize_order/1)
    {:ok, normalized}
  end

  def parse_orders(orders) when is_list(orders) do
    normalized = Enum.map(orders, &normalize_order/1)
    {:ok, normalized}
  end

  def parse_orders(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit order book response.

  ## Examples

      response = %{
        "result" => %{
          "timestamp" => 1554373962454,
          "instrument_name" => "BTC-PERPETUAL",
          "change_id" => 38476410,
          "bids" => [
            ["new", 5000.5, 10],
            ["change", 5000.0, 5]
          ],
          "asks" => [
            ["delete", 5001.0, 0]
          ]
        }
      }
      {:ok, orderbook} = parse_order_book(response)
  """
  @spec parse_order_book(map()) :: {:ok, map()} | {:error, term()}
  def parse_order_book(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_order_book(%{"result" => result}) when is_map(result) do
    {:ok, normalize_keys(result)}
  end

  def parse_order_book(data) when is_map(data) do
    {:ok, normalize_keys(data)}
  end

  def parse_order_book(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit ticker response.

  ## Examples

      response = %{
        "result" => %{
          "timestamp" => 1554373962454,
          "stats" => %{
            "volume" => 0.49355866,
            "price_change" => -0.0075,
            "low" => 10056.5,
            "high" => 10060.0
          },
          "state" => "open",
          "last_price" => 10058.5,
          "instrument_name" => "BTC-PERPETUAL",
          "best_bid_price" => 10057.0,
          "best_ask_price" => 10058.5
        }
      }
      {:ok, ticker} = parse_ticker(response)
  """
  @spec parse_ticker(map()) :: {:ok, map()} | {:error, term()}
  def parse_ticker(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_ticker(%{"result" => result}) when is_map(result) do
    normalized = normalize_ticker(result)
    {:ok, normalized}
  end

  def parse_ticker(data) when is_map(data) do
    normalized = normalize_ticker(data)
    {:ok, normalized}
  end

  def parse_ticker(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit instruments list response.

  ## Examples

      response = %{
        "result" => [
          %{
            "instrument_name" => "BTC-PERPETUAL",
            "kind" => "future",
            "base_currency" => "BTC",
            "quote_currency" => "USD",
            "settlement_period" => "perpetual"
          }
        ]
      }
      {:ok, instruments} = parse_instruments(response)
  """
  @spec parse_instruments(map() | list()) :: {:ok, list(map())} | {:error, term()}
  def parse_instruments(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_instruments(%{"result" => instruments}) when is_list(instruments) do
    {:ok, Enum.map(instruments, &normalize_keys/1)}
  end

  def parse_instruments(instruments) when is_list(instruments) do
    {:ok, Enum.map(instruments, &normalize_keys/1)}
  end

  def parse_instruments(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit trades list response.

  Handles both public trades and user trades.

  ## Examples

      response = %{
        "result" => %{
          "trades" => [
            %{
              "trade_id" => "ETH-34066",
              "timestamp" => 1550657340846,
              "direction" => "buy",
              "price" => 143.81,
              "amount" => 10
            }
          ]
        }
      }
      {:ok, trades} = parse_trades(response)
  """
  @spec parse_trades(map() | list()) :: {:ok, list(map())} | {:error, term()}
  def parse_trades(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_trades(%{"result" => %{"trades" => trades}}) when is_list(trades) do
    normalized = Enum.map(trades, &normalize_trade/1)
    {:ok, normalized}
  end

  def parse_trades(%{"result" => trades}) when is_list(trades) do
    normalized = Enum.map(trades, &normalize_trade/1)
    {:ok, normalized}
  end

  def parse_trades(trades) when is_list(trades) do
    normalized = Enum.map(trades, &normalize_trade/1)
    {:ok, normalized}
  end

  def parse_trades(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit account summary response.

  ## Examples

      response = %{
        "result" => %{
          "total_pl" => 0,
          "margin_balance" => 0.1,
          "equity" => 0.1,
          "available_funds" => 0.1
        }
      }
      {:ok, account} = parse_account_summary(response)
  """
  @spec parse_account_summary(map()) :: {:ok, map()} | {:error, term()}
  def parse_account_summary(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_account_summary(%{"result" => result}) when is_map(result) do
    {:ok, normalize_keys(result)}
  end

  def parse_account_summary(data) when is_map(data) do
    {:ok, normalize_keys(data)}
  end

  def parse_account_summary(_), do: {:error, :invalid_format}

  @doc """
  Parses a Deribit positions list response.

  ## Examples

      response = %{
        "result" => [
          %{
            "instrument_name" => "BTC-PERPETUAL",
            "size" => 10,
            "direction" => "buy",
            "average_price" => 50000,
            "mark_price" => 51000
          }
        ]
      }
      {:ok, positions} = parse_positions(response)
  """
  @spec parse_positions(map() | list()) :: {:ok, list(map())} | {:error, term()}
  def parse_positions(%{"error" => _} = response), do: {:error, normalize_keys(response)}

  def parse_positions(%{"result" => positions}) when is_list(positions) do
    {:ok, Enum.map(positions, &normalize_keys/1)}
  end

  def parse_positions(positions) when is_list(positions) do
    {:ok, Enum.map(positions, &normalize_keys/1)}
  end

  def parse_positions(_), do: {:error, :invalid_format}

  # Private normalization functions

  @spec normalize_order(map()) :: map()
  defp normalize_order(order) when is_map(order) do
    order
    |> normalize_keys()
    |> normalize_enum_field(:order_state)
    |> normalize_enum_field(:order_type)
    |> normalize_enum_field(:direction)
    |> normalize_enum_field(:time_in_force)
  end

  @spec normalize_ticker(map()) :: map()
  defp normalize_ticker(ticker) when is_map(ticker) do
    ticker
    |> normalize_keys()
    |> normalize_enum_field(:state)
  end

  @spec normalize_trade(map()) :: map()
  defp normalize_trade(trade) when is_map(trade) do
    trade
    |> normalize_keys()
    |> normalize_enum_field(:direction)
  end

  @spec normalize_enum_field(map(), atom()) :: map()
  defp normalize_enum_field(map, field) when is_map(map) do
    case Map.get(map, field) do
      value when is_binary(value) ->
        Map.put(map, field, normalize_enum_value(value))

      _ ->
        map
    end
  end
end
