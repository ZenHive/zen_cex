alias ZenCex.Health

IO.puts("Testing Health.get_server_time(:binance) directly...")
result = Health.get_server_time(:binance)
IO.inspect(result, label: "Result")

case result do
  {:ok, time} -> 
    IO.puts("Success! Server time: #{time}")
  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
