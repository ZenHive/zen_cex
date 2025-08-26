alias ZenCex.Adapters.Bybit.Unified

IO.puts("Testing Bybit order placement on testnet...")

# First check wallet balance
IO.puts("\n1. Checking wallet balance...")
case Unified.get_wallet_balance(%{accountType: "UNIFIED"}) do
  {:ok, result} ->
    IO.puts("✓ Got wallet balance")
    if result["list"] && length(result["list"]) > 0 do
      account = hd(result["list"])
      IO.puts("Account type: #{account["accountType"]}")
      if account["coin"] && length(account["coin"]) > 0 do
        Enum.each(Enum.take(account["coin"], 3), fn coin ->
          IO.puts("  #{coin["coin"]}: #{coin["walletBalance"]} (available: #{coin["availableToWithdraw"]})")
        end)
      end
    end
  {:error, reason} ->
    IO.puts("✗ Error getting balance: #{inspect(reason)}")
end

# Try to place a test order
IO.puts("\n2. Placing a test order (BTCUSDT spot, far from market price)...")
order_id = "test_#{:erlang.system_time(:millisecond)}"

case Unified.place_order(%{
  category: "spot",
  symbol: "BTCUSDT", 
  side: "Buy",
  orderType: "Limit",
  qty: "0.001",
  price: "10000",  # Far below market price to avoid fill
  orderLinkId: order_id
}) do
  {:ok, data} ->
    IO.puts("✓ Order placed successfully!")
    IO.puts("  Order ID: #{data["orderId"]}")
    IO.puts("  Order Link ID: #{data["orderLinkId"]}")
    
    # Cancel the order
    IO.puts("\n3. Canceling the test order...")
    case Unified.cancel_order(%{
      category: "spot",
      symbol: "BTCUSDT",
      orderId: data["orderId"]
    }) do
      {:ok, _} ->
        IO.puts("✓ Order canceled successfully!")
      {:error, reason} ->
        IO.puts("✗ Error canceling: #{inspect(reason)}")
    end
    
  {:error, {:insufficient_balance, msg}} ->
    IO.puts("✗ Insufficient balance: #{msg}")
    IO.puts("  Please add more test funds from the Bybit testnet faucet")
    
  {:error, reason} ->
    IO.puts("✗ Error placing order: #{inspect(reason)}")
end

IO.puts("\nTest complete!")
