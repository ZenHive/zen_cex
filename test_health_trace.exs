alias ZenCex.{Endpoints, HTTP}

IO.puts("Building request...")
{:ok, request} = Endpoints.build_request(:binance, :server_time)

IO.puts("Executing request...")
try do
  response = Req.request!(request)
  IO.inspect(response, label: "Response", limit: 3)
  
  IO.puts("\nParsing response...")
  case HTTP.parse_response(response, :json) do
    {:ok, body} -> 
      IO.inspect(body, label: "Parsed body")
      
      # Try to parse server time
      IO.puts("Parsing server time...")
      case ZenCex.Health.parse_server_time(body, :binance) do
        {:ok, time} -> IO.puts("Server time: #{time}")
        {:error, err} -> IO.puts("Parse error: #{inspect(err)}")
      end
    {:error, err} -> 
      IO.puts("Parse response error: #{inspect(err)}")
  end
rescue
  e ->
    IO.puts("Error: #{Exception.message(e)}")
    IO.puts("Stack: #{inspect(__STACKTRACE__, limit: 5)}")
end
