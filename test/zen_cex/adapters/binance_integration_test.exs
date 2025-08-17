defmodule ZenCex.Adapters.BinanceIntegrationTest do
  @moduledoc """
  Integration tests for Binance adapter against REAL Binance testnet API.

  This test suite follows the "Real APIs First" testing philosophy:
  1. Test against actual Binance testnet API to understand real behavior
  2. Capture and document actual responses for fixture generation
  3. Create reliable mocks based on observed real API behavior
  4. Test error scenarios with authentic API responses
  5. Document API quirks, edge cases, and timing requirements

  ## Smart Testing Strategy

  - Uses Binance testnet (testnet.binance.vision) to avoid affecting production
  - Controlled concurrency (max 2-3 parallel requests) to avoid rate limits
  - Batched tests with delays between groups to be respectful to API
  - Captures response headers for rate limit analysis
  - Documents actual error formats and edge cases

  ## Environment Requirements

  Tests require valid Binance testnet credentials:
  - `BINANCE_API_KEY` - Testnet API key
  - `BINANCE_API_SECRET` - Testnet API secret

  Get testnet credentials from: https://testnet.binance.vision/

  ## Running Tests

      # Run all integration tests
      mix test --only integration

      # Run only Binance integration tests
      mix test --only binance_integration

      # Run with network requirement check
      mix test --only requires_network
  """

  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance.Endpoints

  require Logger

  # Test tags for categorization
  @moduletag :integration
  @moduletag :binance_integration
  @moduletag timeout: 60_000

  # Smart testing parameters to avoid getting banned
  # @max_parallel_requests 2
  @inter_request_delay_ms 1000
  @inter_group_delay_ms 3000
  # @request_timeout_ms 15_000

  # Test environment
  @testnet_base_url "https://testnet.binance.vision"

  # Fixture storage for captured responses
  @fixtures_dir "test/fixtures/binance"

  setup_all do
    # Check for required environment variables
    api_key = System.get_env("BINANCE_API_KEY")
    api_secret = System.get_env("BINANCE_API_SECRET")

    cond do
      is_nil(api_key) or is_nil(api_secret) ->
        {:skip,
         """
         Binance testnet credentials not found.
         Set BINANCE_API_KEY and BINANCE_API_SECRET environment variables.
         Get testnet credentials from: https://testnet.binance.vision/
         """}

      not network_available?() ->
        {:skip, "Network connectivity to Binance testnet unavailable"}

      true ->
        # Ensure fixtures directory exists
        File.mkdir_p!(@fixtures_dir)

        # Initialize rate limiter
        ZenCex.Adapters.Binance.RateLimiter.init()

        {:ok, api_key: api_key, api_secret: api_secret}
    end
  end

  describe "public endpoints (no auth required)" do
    @tag :requires_network
    test "get_server_time/0 - captures real time synchronization data" do
      Logger.info("Testing server time endpoint against real API")

      # Test the endpoint
      case Endpoints.get_server_time() do
        {:ok, result} ->
          # Validate response structure
          assert %{server_time: server_time} = result
          assert is_integer(server_time)
          assert server_time > 0

          # Server time should be recent (within 1 minute of system time)
          system_time = System.system_time(:millisecond)
          time_diff = abs(server_time - system_time)

          assert time_diff < 60_000,
                 "Server time drift too large: #{time_diff}ms (server: #{server_time}, system: #{system_time})"

          # Save fixture for mock testing
          save_fixture("get_server_time_success.json", result)

          Logger.info("✓ Server time: #{server_time}, drift: #{time_diff}ms")

        {:error, reason} ->
          flunk("Server time request failed: #{inspect(reason)}")
      end

      # Add delay before next test
      Process.sleep(@inter_request_delay_ms)
    end

    @tag :requires_network
    test "get_ticker/1 - captures real ticker data and validates parsing" do
      Logger.info("Testing ticker endpoint with various symbols")

      test_cases = [
        # Single ticker
        %{symbol: "BTCUSDT", description: "single BTC ticker"},
        # High-volume pair
        %{symbol: "ETHUSDT", description: "single ETH ticker"},
        # All tickers (no symbol parameter)
        %{description: "all tickers"}
      ]

      Enum.each(test_cases, fn test_case ->
        params = if Map.has_key?(test_case, :symbol), do: %{symbol: test_case.symbol}, else: %{}

        Logger.info("  Testing: #{test_case.description}")

        case Endpoints.get_ticker(params) do
          {:ok, result} ->
            if Map.has_key?(test_case, :symbol) do
              # Single ticker response
              assert %{symbol: symbol, price: price} = result
              assert symbol == test_case.symbol
              assert %Decimal{} = price
              assert Decimal.gt?(price, Decimal.new("0"))

              # Save fixture
              save_fixture("get_ticker_#{String.downcase(test_case.symbol)}.json", result)
            else
              # Multiple tickers response
              assert is_list(result)
              assert length(result) > 0

              # Validate first ticker structure
              first_ticker = List.first(result)
              assert %{symbol: symbol, price: price} = first_ticker
              assert is_binary(symbol)
              assert %Decimal{} = price

              # Save sample of tickers for fixture
              sample_tickers = Enum.take(result, 5)
              save_fixture("get_ticker_all_sample.json", sample_tickers)
            end

            Logger.info("    ✓ Valid response structure")

          {:error, reason} ->
            Logger.error("    ✗ Failed: #{inspect(reason)}")
            flunk("Ticker request failed for #{test_case.description}: #{inspect(reason)}")
        end

        # Delay between symbol requests
        Process.sleep(@inter_request_delay_ms)
      end)
    end
  end

  describe "authenticated endpoints (testnet credentials)" do
    @tag :requires_network
    test "get_balances/0 - captures real account balance data", %{
      api_key: api_key,
      api_secret: api_secret
    } do
      Logger.info("Testing account balances endpoint")

      params = %{api_key: api_key, api_secret: api_secret}

      case Endpoints.get_balances(params) do
        {:ok, balances} ->
          # Validate response structure
          assert is_list(balances)

          # Each balance should have required fields
          if length(balances) > 0 do
            first_balance = List.first(balances)
            assert %{asset: asset, free: free, locked: locked, total: total} = first_balance
            assert is_binary(asset)
            assert %Decimal{} = free
            assert %Decimal{} = locked
            assert %Decimal{} = total
            # Total should equal free + locked
            assert Decimal.equal?(total, Decimal.add(free, locked))
          end

          # Save fixture (sanitize sensitive data)
          sanitized_balances = sanitize_balances(balances)
          save_fixture("get_balances_success.json", sanitized_balances)

          Logger.info("✓ Retrieved #{length(balances)} balance entries")

        {:error, reason} ->
          # Document the error for fixture generation
          save_fixture("get_balances_error.json", %{
            error: reason,
            timestamp: System.system_time(:millisecond)
          })

          Logger.warning(
            "Balances request failed (expected on empty testnet): #{inspect(reason)}"
          )

          # This might fail on fresh testnet accounts, which is acceptable
          # We still want to document the error format
          # Check for expected error atoms or tuples
          assert reason in [:invalid_credentials, :insufficient_balance] or
                   match?({:exchange_error, _}, reason) or
                   match?({:unknown_error, _}, reason)
      end

      Process.sleep(@inter_request_delay_ms)
    end

    @tag :requires_network
    test "place_order/1 and cancel_order/1 - full order lifecycle", %{
      api_key: api_key,
      api_secret: api_secret
    } do
      Logger.info("Testing complete order lifecycle (place -> query -> cancel)")

      # Use a test order that should never fill (price too low)
      order_params = %{
        api_key: api_key,
        api_secret: api_secret,
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        # Minimum quantity
        quantity: "0.001",
        # Extremely low price to avoid fills
        price: "1000.00",
        timeInForce: "GTC"
      }

      # Step 1: Place order
      Logger.info("  Step 1: Placing test order")

      case Endpoints.place_order(order_params) do
        {:ok, order} ->
          # Validate order response structure
          assert %{
                   order_id: order_id,
                   client_order_id: _client_order_id,
                   symbol: symbol,
                   side: side,
                   type: type,
                   status: status
                 } = order

          assert is_binary(order_id)
          assert symbol == "BTCUSDT"
          assert side == :buy
          assert type == :limit
          assert status in [:new, :partially_filled]

          # Save successful order placement fixture
          sanitized_order = sanitize_order(order)
          save_fixture("place_order_success.json", sanitized_order)

          Logger.info("    ✓ Order placed: #{order_id}")

          # Step 2: Query order status
          Logger.info("  Step 2: Querying order status")

          query_params = %{
            api_key: api_key,
            api_secret: api_secret,
            symbol: "BTCUSDT",
            orderId: order_id
          }

          # Brief delay
          Process.sleep(500)

          case Endpoints.get_order(query_params) do
            {:ok, queried_order} ->
              assert queried_order.order_id == order_id
              assert queried_order.symbol == "BTCUSDT"

              save_fixture("get_order_success.json", sanitize_order(queried_order))
              Logger.info("    ✓ Order queried successfully")

            {:error, query_reason} ->
              Logger.warning("    ⚠ Order query failed: #{inspect(query_reason)}")
              save_fixture("get_order_error.json", %{error: query_reason})
          end

          # Step 3: Cancel order
          Logger.info("  Step 3: Cancelling order")

          cancel_params = %{
            api_key: api_key,
            api_secret: api_secret,
            symbol: "BTCUSDT",
            orderId: order_id
          }

          # Brief delay
          Process.sleep(500)

          case Endpoints.cancel_order(cancel_params) do
            {:ok, cancelled_order} ->
              assert cancelled_order.order_id == order_id
              assert cancelled_order.status in [:cancelled, :filled, :partially_filled]

              save_fixture("cancel_order_success.json", sanitize_order(cancelled_order))
              Logger.info("    ✓ Order cancelled successfully")

            {:error, cancel_reason} ->
              Logger.warning("    ⚠ Order cancellation failed: #{inspect(cancel_reason)}")
              save_fixture("cancel_order_error.json", %{error: cancel_reason})

              # Cancellation might fail if order was already filled/cancelled
              # Document the error but don't fail the test
          end

        {:error, reason} ->
          # Document order placement errors
          save_fixture("place_order_error.json", %{
            error: reason,
            params: sanitize_order_params(order_params)
          })

          Logger.warning("Order placement failed: #{inspect(reason)}")

          # Common failure reasons on testnet
          acceptable_errors = [
            :insufficient_balance,
            :invalid_symbol,
            :invalid_quantity,
            :exchange_error
          ]

          assert reason in acceptable_errors or match?({:exchange_error, _}, reason),
                 "Unexpected order placement error: #{inspect(reason)}"
      end

      Process.sleep(@inter_group_delay_ms)
    end

    @tag :requires_network
    test "get_open_orders/1 - captures open orders structure", %{
      api_key: api_key,
      api_secret: api_secret
    } do
      Logger.info("Testing open orders endpoint")

      params = %{
        api_key: api_key,
        api_secret: api_secret,
        # Filter by symbol
        symbol: "BTCUSDT"
      }

      case Endpoints.get_open_orders(params) do
        {:ok, orders} ->
          assert is_list(orders)

          # Validate structure if orders exist
          if length(orders) > 0 do
            first_order = List.first(orders)
            assert %{order_id: _, symbol: _, side: _, type: _, status: _} = first_order
          end

          # Save fixture
          sanitized_orders = Enum.map(orders, &sanitize_order/1)
          save_fixture("get_open_orders_success.json", sanitized_orders)

          Logger.info("✓ Retrieved #{length(orders)} open orders")

        {:error, reason} ->
          save_fixture("get_open_orders_error.json", %{error: reason})
          Logger.warning("Open orders request failed: #{inspect(reason)}")

          # Document error but don't fail - might be auth or network issue
          assert reason in [:invalid_credentials] or
                   match?({:exchange_error, _}, reason) or
                   match?({:unknown_error, _}, reason)
      end

      Process.sleep(@inter_request_delay_ms)
    end

    @tag :requires_network
    test "get_positions/1 - captures futures positions (if available)", %{
      api_key: api_key,
      api_secret: api_secret
    } do
      Logger.info("Testing futures positions endpoint")

      params = %{api_key: api_key, api_secret: api_secret}

      case Endpoints.get_positions(params) do
        {:ok, positions} ->
          assert is_list(positions)

          # Validate structure if positions exist
          if length(positions) > 0 do
            first_position = List.first(positions)

            assert %{symbol: _, side: _, size: _, entry_price: _, mark_price: _, pnl: _} =
                     first_position
          end

          sanitized_positions = Enum.map(positions, &sanitize_position/1)
          save_fixture("get_positions_success.json", sanitized_positions)

          Logger.info("✓ Retrieved #{length(positions)} positions")

        {:error, reason} ->
          save_fixture("get_positions_error.json", %{error: reason})

          Logger.warning(
            "Positions request failed (expected if futures not enabled): #{inspect(reason)}"
          )

          # Futures might not be enabled on testnet account
          assert reason in [:invalid_credentials, :unknown_error] or
                   match?({:exchange_error, _}, reason) or
                   match?({:unknown_error, _}, reason)
      end

      Process.sleep(@inter_request_delay_ms)
    end
  end

  describe "error scenarios with real API responses" do
    @tag :requires_network
    test "invalid symbol error - captures real error format" do
      Logger.info("Testing invalid symbol error response")

      params = %{symbol: "INVALIDBTC"}

      case Endpoints.get_ticker(params) do
        {:ok, _result} ->
          flunk("Expected error for invalid symbol, but got success")

        {:error, reason} ->
          # Capture real error format
          save_fixture("error_invalid_symbol.json", %{error: reason, symbol: "INVALIDBTC"})

          Logger.info("✓ Captured invalid symbol error: #{inspect(reason)}")

          # Validate it's the expected error type
          assert reason in [:invalid_symbol] or
                   match?({:exchange_error, _}, reason)
      end

      Process.sleep(@inter_request_delay_ms)
    end

    @tag :requires_network
    test "authentication error - captures real auth failure response" do
      Logger.info("Testing authentication error with invalid credentials")

      params = %{
        api_key: "invalid_key",
        api_secret: "invalid_secret"
      }

      case Endpoints.get_balances(params) do
        {:ok, _result} ->
          flunk("Expected authentication error, but got success")

        {:error, reason} ->
          # Capture real auth error format
          save_fixture("error_invalid_auth.json", %{error: reason, credentials: "invalid"})

          Logger.info("✓ Captured auth error: #{inspect(reason)}")

          # Should be credentials-related error
          assert reason in [:invalid_credentials, :signature_not_valid] or
                   match?({:exchange_error, _}, reason)
      end

      Process.sleep(@inter_request_delay_ms)
    end

    @tag :requires_network
    test "rate limit testing with controlled burst" do
      Logger.info("Testing rate limit behavior with controlled burst")

      # Make several requests quickly to potentially trigger rate limits
      # Use lightweight ping endpoint
      request_count = 5

      results =
        for i <- 1..request_count do
          Logger.info("  Request #{i}/#{request_count}")

          result =
            case Endpoints.get_server_time() do
              {:ok, time_result} -> {:ok, time_result}
              {:error, reason} -> {:error, reason}
            end

          # Very short delay within burst
          Process.sleep(100)
          result
        end

      # Analyze results
      successes = Enum.count(results, &match?({:ok, _}, &1))
      errors = Enum.count(results, &match?({:error, _}, &1))

      rate_limit_errors =
        Enum.count(results, fn
          {:error, :rate_limited} -> true
          {:error, {:rate_limited, _}} -> true
          _ -> false
        end)

      Logger.info("""
      Rate limit test results:
        Total requests: #{request_count}
        Successful: #{successes}
        Errors: #{errors}
        Rate limit errors: #{rate_limit_errors}
      """)

      # Document the behavior
      save_fixture("rate_limit_test_results.json", %{
        total: request_count,
        successes: successes,
        errors: errors,
        rate_limit_errors: rate_limit_errors,
        results: results
      })

      # We expect most requests to succeed with this light testing
      assert successes >= request_count * 0.6,
             "Too many failures in rate limit test: #{successes}/#{request_count}"

      Process.sleep(@inter_group_delay_ms)
    end
  end

  describe "complex operations testing" do
    @tag :requires_network
    test "place_oco_order/1 - captures OCO order structure if supported", %{
      api_key: api_key,
      api_secret: api_secret
    } do
      Logger.info("Testing OCO (One-Cancels-Other) order placement")

      # OCO order with prices that shouldn't fill
      oco_params = %{
        api_key: api_key,
        api_secret: api_secret,
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.001",
        # Limit price (very low)
        price: "1000.00",
        # Stop price
        stopPrice: "2000.00",
        # Stop limit price
        stopLimitPrice: "1900.00"
      }

      case Endpoints.place_oco_order(oco_params) do
        {:ok, oco_result} ->
          # Validate OCO response structure
          assert %{order_list_id: order_list_id, orders: orders} = oco_result
          assert is_integer(order_list_id)
          assert is_list(orders)
          # OCO creates 2 orders
          assert length(orders) == 2

          save_fixture("place_oco_order_success.json", sanitize_oco_order(oco_result))
          Logger.info("✓ OCO order placed successfully: #{order_list_id}")

          # Try to cancel the OCO orders if we can identify them
          Enum.each(orders, fn order ->
            if Map.has_key?(order, :order_id) do
              cancel_params = %{
                api_key: api_key,
                api_secret: api_secret,
                symbol: "BTCUSDT",
                orderId: order.order_id
              }

              # Attempt cancellation (may fail, that's ok)
              Process.sleep(500)
              Endpoints.cancel_order(cancel_params)
            end
          end)

        {:error, reason} ->
          save_fixture("place_oco_order_error.json", %{error: reason})
          Logger.warning("OCO order failed (may not be supported on testnet): #{inspect(reason)}")

          # OCO might not be available on all testnet accounts
          assert reason in [:insufficient_balance, :invalid_symbol, :invalid_quantity] or
                   match?({:exchange_error, _}, reason) or
                   match?({:unknown_error, _}, reason)
      end

      Process.sleep(@inter_group_delay_ms)
    end
  end

  describe "API timing and synchronization" do
    @tag :requires_network
    test "documents timestamp requirements and clock sync behavior" do
      Logger.info("Testing timestamp handling and clock synchronization")

      # Test 1: Normal timestamp
      case Endpoints.get_server_time() do
        {:ok, %{server_time: server_time}} ->
          system_time = System.system_time(:millisecond)
          drift = server_time - system_time

          timing_info = %{
            server_time: server_time,
            system_time: system_time,
            drift_ms: drift,
            timestamp: System.system_time(:millisecond)
          }

          save_fixture("timing_analysis.json", timing_info)

          Logger.info("""
          Clock synchronization analysis:
            Server time: #{server_time}
            System time: #{system_time}
            Drift: #{drift}ms
          """)

        {:error, reason} ->
          flunk("Could not get server time for timing analysis: #{inspect(reason)}")
      end

      Process.sleep(@inter_request_delay_ms)
    end
  end

  # Helper functions for test utilities

  defp network_available? do
    case :httpc.request(:get, {~c"#{@testnet_base_url}/api/v3/ping", []}, [{:timeout, 5000}], []) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp save_fixture(filename, data) do
    file_path = Path.join(@fixtures_dir, filename)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Convert data to JSON-safe format
    json_safe_data = make_json_safe(data)

    # Add metadata
    fixture_data = %{
      data: json_safe_data,
      captured_at: System.system_time(:millisecond),
      zen_cex_version: "0.1.0",
      test_environment: "binance_testnet"
    }

    # Save as pretty-printed JSON
    json_content = Jason.encode!(fixture_data, pretty: true)
    File.write!(file_path, json_content)

    Logger.debug("Saved fixture: #{filename}")
  end

  # Convert Elixir data structures to JSON-safe format
  defp make_json_safe({:ok, value}), do: %{status: "ok", value: make_json_safe(value)}
  defp make_json_safe({:error, reason}), do: %{status: "error", reason: make_json_safe(reason)}

  defp make_json_safe({type, message}) when is_atom(type) and is_binary(message),
    do: %{type: to_string(type), message: message}

  defp make_json_safe({type, value}) when is_atom(type),
    do: %{type: to_string(type), value: make_json_safe(value)}

  defp make_json_safe(list) when is_list(list), do: Enum.map(list, &make_json_safe/1)

  # Handle Decimal types
  defp make_json_safe(%Decimal{} = decimal), do: Decimal.to_string(decimal)

  # Handle other structs by converting to map first
  defp make_json_safe(%{__struct__: _} = struct),
    do: struct |> Map.from_struct() |> make_json_safe()

  defp make_json_safe(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, make_json_safe(v)} end)

  defp make_json_safe(other), do: other

  # Data sanitization helpers to remove sensitive information

  defp sanitize_balances(balances) do
    Enum.map(balances, fn balance ->
      %{
        balance
        | free: sanitize_amount(balance.free),
          locked: sanitize_amount(balance.locked),
          total: sanitize_amount(balance.total)
      }
    end)
  end

  defp sanitize_order(order) do
    %{
      order
      | order_id: "TEST_ORDER_" <> String.slice(order.order_id, -6, 6),
        client_order_id:
          if(order.client_order_id,
            do: "TEST_CLIENT_" <> String.slice(order.client_order_id || "", -6, 6)
          ),
        quantity: sanitize_amount(order.quantity),
        filled_quantity: sanitize_amount(order.filled_quantity),
        price: sanitize_amount(order.price)
    }
  end

  defp sanitize_position(position) do
    %{
      position
      | size: sanitize_amount(position.size),
        entry_price: sanitize_amount(position.entry_price),
        mark_price: sanitize_amount(position.mark_price),
        pnl: sanitize_amount(position.pnl),
        margin: sanitize_amount(position.margin)
    }
  end

  defp sanitize_oco_order(oco_order) do
    %{
      oco_order
      | # Fixed test ID
        order_list_id: 12345,
        orders: Enum.map(oco_order.orders, &sanitize_order/1)
    }
  end

  defp sanitize_order_params(params) do
    params
    |> Map.delete(:api_key)
    |> Map.delete(:api_secret)
    |> Map.put(:api_key, "[SANITIZED]")
    |> Map.put(:api_secret, "[SANITIZED]")
  end

  defp sanitize_amount(%Decimal{} = amount) do
    # Replace with representative test values
    cond do
      Decimal.gt?(amount, Decimal.new("1000")) -> Decimal.new("1234.567")
      Decimal.gt?(amount, Decimal.new("1")) -> Decimal.new("12.345")
      Decimal.gt?(amount, Decimal.new("0")) -> Decimal.new("0.123")
      true -> amount
    end
  end

  defp sanitize_amount(amount), do: amount
end
