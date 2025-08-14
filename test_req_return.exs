alias ZenCex.{Endpoints, HTTP}

{:ok, request} = Endpoints.build_request(:binance, :server_time)
IO.inspect(request, label: "Request")

result = Req.request!(request)
IO.inspect(result, label: "Result type", limit: 2)

case result do
  %Req.Response{} = resp ->
    IO.puts("Got response directly: #{resp.status}")
  {%Req.Request{}, %Req.Response{} = resp} ->
    IO.puts("Got {request, response} tuple: #{resp.status}")
  other ->
    IO.puts("Got unexpected: #{inspect(other, limit: 2)}")
end
