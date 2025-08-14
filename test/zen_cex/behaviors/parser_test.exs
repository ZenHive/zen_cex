defmodule ZenCex.Behaviors.ParserTest do
  use ExUnit.Case, async: true

  defmodule TestParser do
    @behaviour ZenCex.Behaviors.Parser

    @impl true
    def parse_positions(response) do
      case response do
        %{"positions" => positions} ->
          parsed =
            Enum.map(positions, fn pos ->
              %{
                symbol: pos["symbol"],
                side: String.to_atom(pos["side"]),
                size: Decimal.new(pos["size"]),
                entry_price: Decimal.new(pos["entryPrice"]),
                mark_price: Decimal.new(pos["markPrice"]),
                pnl: Decimal.new(pos["pnl"]),
                margin: Decimal.new(pos["margin"]),
                timestamp: pos["timestamp"]
              }
            end)

          {:ok, parsed}

        _ ->
          {:error, :invalid_format}
      end
    end

    @impl true
    def parse_balances(response) do
      case response do
        %{"balances" => balances} ->
          parsed =
            Enum.map(balances, fn bal ->
              free = Decimal.new(bal["free"])
              locked = Decimal.new(bal["locked"])

              %{
                asset: bal["asset"],
                free: free,
                locked: locked,
                total: Decimal.add(free, locked)
              }
            end)

          {:ok, parsed}

        _ ->
          {:error, :invalid_format}
      end
    end

    @impl true
    def parse_order(response) do
      case response do
        %{"order" => order} ->
          {:ok,
           %{
             order_id: order["orderId"],
             symbol: order["symbol"],
             side: String.to_atom(order["side"]),
             type: String.to_atom(order["type"]),
             price: Decimal.new(order["price"] || "0"),
             quantity: Decimal.new(order["quantity"]),
             status: String.to_atom(order["status"]),
             timestamp: order["timestamp"]
           }}

        _ ->
          {:error, :invalid_format}
      end
    end

    @impl true
    def parse_market_data(data) do
      case data do
        %{"type" => "heartbeat"} ->
          :ignore

        %{"type" => type, "symbol" => symbol, "data" => event_data} ->
          {:ok,
           %{
             type: String.to_atom(type),
             symbol: symbol,
             data: event_data,
             timestamp: System.system_time(:millisecond)
           }}

        _ ->
          {:error, :unknown_message}
      end
    end

    @impl true
    def parse_error(response) do
      case response do
        %{"code" => -2010} -> {:error, :insufficient_balance}
        %{"code" => -1121} -> {:error, :invalid_symbol}
        %{"code" => 429} -> {:error, :rate_limited}
        %{"error" => "unauthorized"} -> {:error, :invalid_credentials}
        %{"error" => error} -> {:error, {:exchange_error, error}}
        _ -> {:error, :unknown_error}
      end
    end
  end

  describe "position parsing" do
    test "parses positions correctly" do
      response = %{
        "positions" => [
          %{
            "symbol" => "BTCUSDT",
            "side" => "long",
            "size" => "0.5",
            "entryPrice" => "50000",
            "markPrice" => "51000",
            "pnl" => "500",
            "margin" => "5000",
            "timestamp" => 1_234_567_890
          }
        ]
      }

      assert {:ok, [position]} = TestParser.parse_positions(response)
      assert position.symbol == "BTCUSDT"
      assert position.side == :long
      assert Decimal.equal?(position.size, Decimal.new("0.5"))
      assert Decimal.equal?(position.entry_price, Decimal.new("50000"))
      assert Decimal.equal?(position.mark_price, Decimal.new("51000"))
      assert Decimal.equal?(position.pnl, Decimal.new("500"))
      assert Decimal.equal?(position.margin, Decimal.new("5000"))
      assert position.timestamp == 1_234_567_890
    end

    test "returns error for invalid position format" do
      assert {:error, :invalid_format} = TestParser.parse_positions(%{})
    end
  end

  describe "balance parsing" do
    test "parses balances correctly" do
      response = %{
        "balances" => [
          %{
            "asset" => "BTC",
            "free" => "0.5",
            "locked" => "0.1"
          },
          %{
            "asset" => "USDT",
            "free" => "1000",
            "locked" => "500"
          }
        ]
      }

      assert {:ok, balances} = TestParser.parse_balances(response)
      assert length(balances) == 2

      btc = Enum.find(balances, &(&1.asset == "BTC"))
      assert Decimal.equal?(btc.free, Decimal.new("0.5"))
      assert Decimal.equal?(btc.locked, Decimal.new("0.1"))
      assert Decimal.equal?(btc.total, Decimal.new("0.6"))

      usdt = Enum.find(balances, &(&1.asset == "USDT"))
      assert Decimal.equal?(usdt.free, Decimal.new("1000"))
      assert Decimal.equal?(usdt.locked, Decimal.new("500"))
      assert Decimal.equal?(usdt.total, Decimal.new("1500"))
    end

    test "returns error for invalid balance format" do
      assert {:error, :invalid_format} = TestParser.parse_balances(%{"wrong" => "format"})
    end
  end

  describe "order parsing" do
    test "parses order correctly" do
      response = %{
        "order" => %{
          "orderId" => "123456",
          "symbol" => "BTCUSDT",
          "side" => "buy",
          "type" => "limit",
          "price" => "50000",
          "quantity" => "0.1",
          "status" => "filled",
          "timestamp" => 1_234_567_890
        }
      }

      assert {:ok, order} = TestParser.parse_order(response)
      assert order.order_id == "123456"
      assert order.symbol == "BTCUSDT"
      assert order.side == :buy
      assert order.type == :limit
      assert Decimal.equal?(order.price, Decimal.new("50000"))
      assert Decimal.equal?(order.quantity, Decimal.new("0.1"))
      assert order.status == :filled
    end

    test "handles market orders without price" do
      response = %{
        "order" => %{
          "orderId" => "123456",
          "symbol" => "BTCUSDT",
          "side" => "buy",
          "type" => "market",
          "price" => nil,
          "quantity" => "0.1",
          "status" => "new",
          "timestamp" => 1_234_567_890
        }
      }

      assert {:ok, order} = TestParser.parse_order(response)
      assert Decimal.equal?(order.price, Decimal.new("0"))
    end
  end

  describe "market data parsing" do
    test "parses market data correctly" do
      data = %{
        "type" => "ticker",
        "symbol" => "BTCUSDT",
        "data" => %{"price" => "50000", "volume" => "100"}
      }

      assert {:ok, parsed} = TestParser.parse_market_data(data)
      assert parsed.type == :ticker
      assert parsed.symbol == "BTCUSDT"
      assert parsed.data["price"] == "50000"
    end

    test "ignores heartbeat messages" do
      assert :ignore = TestParser.parse_market_data(%{"type" => "heartbeat"})
    end

    test "returns error for unknown messages" do
      assert {:error, :unknown_message} = TestParser.parse_market_data(%{"random" => "data"})
    end
  end

  describe "error parsing" do
    test "parses common error codes" do
      assert {:error, :insufficient_balance} = TestParser.parse_error(%{"code" => -2010})
      assert {:error, :invalid_symbol} = TestParser.parse_error(%{"code" => -1121})
      assert {:error, :rate_limited} = TestParser.parse_error(%{"code" => 429})
      assert {:error, :invalid_credentials} = TestParser.parse_error(%{"error" => "unauthorized"})
    end

    test "returns error with details for generic errors" do
      assert {:error, {:exchange_error, "Something went wrong"}} =
               TestParser.parse_error(%{"error" => "Something went wrong"})
    end

    test "returns unknown error for unrecognized format" do
      assert {:error, :unknown_error} = TestParser.parse_error(%{"weird" => "format"})
    end
  end
end
