# Test different Req configurations
IO.puts("Testing Req configurations...")

# This should work - no finch, with connect_options
try do
  req1 = Req.new(
    base_url: "https://api.github.com",
    connect_options: [timeout: 2000],
    receive_timeout: 5000
  )
  IO.puts("✓ Config 1: No finch, with connect_options - SUCCESS")
rescue
  e -> IO.puts("✗ Config 1: #{Exception.message(e)}")
end

# This might fail - finch with connect_options
try do
  req2 = Req.new(
    base_url: "https://api.github.com",
    finch: ZenCex.Finch,
    connect_options: [timeout: 2000],
    receive_timeout: 5000
  )
  IO.puts("✓ Config 2: With finch and connect_options - SUCCESS")
rescue
  e -> IO.puts("✗ Config 2: #{Exception.message(e)}")
end

# This should work - finch without connect_options
try do
  req3 = Req.new(
    base_url: "https://api.github.com",
    finch: ZenCex.Finch,
    receive_timeout: 5000,
    pool_timeout: 1000
  )
  IO.puts("✓ Config 3: With finch, no connect_options - SUCCESS")
rescue
  e -> IO.puts("✗ Config 3: #{Exception.message(e)}")
end
