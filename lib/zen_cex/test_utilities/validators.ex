defmodule ZenCex.TestUtilities.Validators do
  @moduledoc """
  Response structure validators for different exchanges.

  Validates that API responses match expected formats for each exchange.
  """

  import ExUnit.Assertions, only: [assert: 1]

  @doc """
  Validates balance structure for the given exchange.
  """
  @spec assert_valid_balance_structure(map() | list(), atom()) :: :ok
  def assert_valid_balance_structure(data, :binance) when is_map(data) do
    # Single balance
    assert Map.has_key?(data, "asset")
    assert Map.has_key?(data, "free")
    assert Map.has_key?(data, "locked")
    assert is_binary(data["asset"])
    assert is_binary(data["free"])
    assert is_binary(data["locked"])
    :ok
  end

  def assert_valid_balance_structure(data, :binance) when is_list(data) do
    # Multiple balances
    Enum.each(data, &assert_valid_balance_structure(&1, :binance))
    :ok
  end

  def assert_valid_balance_structure(data, :bybit) when is_map(data) do
    # Single balance
    assert Map.has_key?(data, "coin")
    assert Map.has_key?(data, "free") or Map.has_key?(data, "availableToWithdraw")
    assert Map.has_key?(data, "walletBalance")
    assert is_binary(data["coin"])
    :ok
  end

  def assert_valid_balance_structure(data, :bybit) when is_list(data) do
    # Multiple balances
    Enum.each(data, &assert_valid_balance_structure(&1, :bybit))
    :ok
  end

  def assert_valid_balance_structure(_data, _exchange) do
    # Generic validation for unknown exchanges
    :ok
  end

  @doc """
  Validates position structure for the given exchange.
  """
  @spec assert_valid_position_structure(map() | list(), atom()) :: :ok
  def assert_valid_position_structure(data, :binance) when is_map(data) do
    # Single position
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "positionAmt")
    assert Map.has_key?(data, "entryPrice")
    assert Map.has_key?(data, "markPrice")
    assert Map.has_key?(data, "unRealizedProfit")
    assert is_binary(data["symbol"])
    assert is_binary(data["positionAmt"])
    :ok
  end

  def assert_valid_position_structure(data, :binance) when is_list(data) do
    # Multiple positions
    Enum.each(data, &assert_valid_position_structure(&1, :binance))
    :ok
  end

  def assert_valid_position_structure(data, :bybit) when is_map(data) do
    # Single position
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "side")
    assert Map.has_key?(data, "size")
    assert Map.has_key?(data, "avgPrice") or Map.has_key?(data, "entryPrice")
    assert Map.has_key?(data, "markPrice")
    assert is_binary(data["symbol"])
    assert is_binary(data["size"])
    :ok
  end

  def assert_valid_position_structure(data, :bybit) when is_list(data) do
    # Multiple positions
    Enum.each(data, &assert_valid_position_structure(&1, :bybit))
    :ok
  end

  def assert_valid_position_structure(_data, _exchange) do
    # Generic validation
    :ok
  end

  @doc """
  Validates order structure for the given exchange.
  """
  @spec assert_valid_order_structure(map() | list(), atom()) :: :ok
  def assert_valid_order_structure(data, :binance) when is_map(data) do
    # Single order
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "orderId")
    assert Map.has_key?(data, "clientOrderId")
    assert Map.has_key?(data, "price")
    assert Map.has_key?(data, "origQty")
    assert Map.has_key?(data, "status")
    assert Map.has_key?(data, "type")
    assert Map.has_key?(data, "side")
    assert is_binary(data["symbol"])
    assert is_binary(data["side"])
    :ok
  end

  def assert_valid_order_structure(data, :binance) when is_list(data) do
    # Multiple orders
    Enum.each(data, &assert_valid_order_structure(&1, :binance))
    :ok
  end

  def assert_valid_order_structure(data, :bybit) when is_map(data) do
    # Single order
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "orderId")
    assert Map.has_key?(data, "orderLinkId")
    assert Map.has_key?(data, "price")
    assert Map.has_key?(data, "qty")
    assert Map.has_key?(data, "orderStatus")
    assert Map.has_key?(data, "orderType")
    assert Map.has_key?(data, "side")
    assert is_binary(data["symbol"])
    assert is_binary(data["side"])
    :ok
  end

  def assert_valid_order_structure(data, :bybit) when is_list(data) do
    # Multiple orders
    Enum.each(data, &assert_valid_order_structure(&1, :bybit))
    :ok
  end

  def assert_valid_order_structure(_data, _exchange) do
    # Generic validation
    :ok
  end

  @doc """
  Validates kline/candlestick structure for the given exchange.
  """
  @spec assert_valid_kline_structure(list(), atom()) :: :ok
  def assert_valid_kline_structure(data, :binance) when is_list(data) do
    # Binance returns array of arrays, each with 12 elements
    if is_list(List.first(data)) do
      # Multiple klines
      Enum.each(data, fn kline ->
        assert length(kline) == 12
        # Open time
        assert is_integer(Enum.at(kline, 0))
        # Open
        assert is_binary(Enum.at(kline, 1))
        # High
        assert is_binary(Enum.at(kline, 2))
        # Low
        assert is_binary(Enum.at(kline, 3))
        # Close
        assert is_binary(Enum.at(kline, 4))
        # Volume
        assert is_binary(Enum.at(kline, 5))
      end)
    else
      # Single kline
      assert length(data) == 12
    end

    :ok
  end

  def assert_valid_kline_structure(data, :bybit) when is_list(data) do
    # Bybit returns array of arrays, each with 7 elements
    if is_list(List.first(data)) do
      # Multiple klines
      Enum.each(data, fn kline ->
        assert length(kline) == 7
        # Start time
        assert is_binary(Enum.at(kline, 0))
        # Open
        assert is_binary(Enum.at(kline, 1))
        # High
        assert is_binary(Enum.at(kline, 2))
        # Low
        assert is_binary(Enum.at(kline, 3))
        # Close
        assert is_binary(Enum.at(kline, 4))
        # Volume
        assert is_binary(Enum.at(kline, 5))
      end)
    else
      # Single kline
      assert length(data) == 7
    end

    :ok
  end

  def assert_valid_kline_structure(_data, _exchange) do
    # Generic validation
    :ok
  end

  @doc """
  Validates ticker structure for the given exchange.
  """
  @spec assert_valid_ticker_structure(map(), atom()) :: :ok
  def assert_valid_ticker_structure(data, :binance) when is_map(data) do
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "price")
    assert is_binary(data["symbol"])
    assert is_binary(data["price"])
    :ok
  end

  def assert_valid_ticker_structure(data, :bybit) when is_map(data) do
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "lastPrice")
    assert is_binary(data["symbol"])
    assert is_binary(data["lastPrice"])
    :ok
  end

  def assert_valid_ticker_structure(_data, _exchange) do
    # Generic validation
    :ok
  end

  @doc """
  Validates order book structure for the given exchange.
  """
  @spec assert_valid_order_book_structure(map(), atom()) :: :ok
  def assert_valid_order_book_structure(data, :binance) when is_map(data) do
    assert Map.has_key?(data, "bids")
    assert Map.has_key?(data, "asks")
    assert is_list(data["bids"])
    assert is_list(data["asks"])

    # Validate bid/ask format (array of [price, quantity])
    if length(data["bids"]) > 0 do
      [price, qty | _] = List.first(data["bids"])
      assert is_binary(price)
      assert is_binary(qty)
    end

    if length(data["asks"]) > 0 do
      [price, qty | _] = List.first(data["asks"])
      assert is_binary(price)
      assert is_binary(qty)
    end

    :ok
  end

  def assert_valid_order_book_structure(data, :bybit) when is_map(data) do
    assert Map.has_key?(data, "b") or Map.has_key?(data, "bids")
    assert Map.has_key?(data, "a") or Map.has_key?(data, "asks")

    bids = data["b"] || data["bids"]
    asks = data["a"] || data["asks"]

    assert is_list(bids)
    assert is_list(asks)

    # Validate bid/ask format (array of [price, size])
    if length(bids) > 0 do
      [price, size | _] = List.first(bids)
      assert is_binary(price)
      assert is_binary(size)
    end

    if length(asks) > 0 do
      [price, size | _] = List.first(asks)
      assert is_binary(price)
      assert is_binary(size)
    end

    :ok
  end

  def assert_valid_order_book_structure(_data, _exchange) do
    # Generic validation
    :ok
  end

  @doc """
  Validates funding rate structure for the given exchange.
  """
  @spec assert_valid_funding_rate_structure(map() | list(), atom()) :: :ok
  def assert_valid_funding_rate_structure(data, :binance) when is_map(data) do
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "fundingRate")
    assert Map.has_key?(data, "fundingTime")
    assert is_binary(data["symbol"])
    assert is_binary(data["fundingRate"])
    :ok
  end

  def assert_valid_funding_rate_structure(data, :binance) when is_list(data) do
    Enum.each(data, &assert_valid_funding_rate_structure(&1, :binance))
    :ok
  end

  def assert_valid_funding_rate_structure(data, :bybit) when is_map(data) do
    assert Map.has_key?(data, "symbol")
    assert Map.has_key?(data, "fundingRate")
    assert Map.has_key?(data, "nextFundingTime")
    assert is_binary(data["symbol"])
    assert is_binary(data["fundingRate"])
    :ok
  end

  def assert_valid_funding_rate_structure(data, :bybit) when is_list(data) do
    Enum.each(data, &assert_valid_funding_rate_structure(&1, :bybit))
    :ok
  end

  def assert_valid_funding_rate_structure(_data, _exchange) do
    # Generic validation
    :ok
  end
end
