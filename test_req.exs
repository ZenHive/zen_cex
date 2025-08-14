alias ZenCex.{Endpoints, HTTP}

{:ok, request} = Endpoints.build_request(:binance, :server_time)
IO.inspect(request, label: "Request before")

try do
  response = Req.request!(request)
  IO.inspect(response, label: "Response")
catch
  error -> IO.inspect(error, label: "Error")
end
