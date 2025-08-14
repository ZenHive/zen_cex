defmodule TestStep do
  def test_step(request) do
    IO.puts("Test step called")
    {:ok, request}  # This is WRONG for a request step!
  end
  
  def test_step_correct(request) do
    IO.puts("Test step correct called")
    request  # This is CORRECT for a request step!
  end
end

request = Req.new(url: "https://httpbin.org/get")
  |> Req.Request.prepend_request_steps(test: &TestStep.test_step/1)

try do
  response = Req.request!(request)
  IO.inspect(response.status)
rescue
  e -> IO.inspect(e, label: "Error with wrong step")
end

request2 = Req.new(url: "https://httpbin.org/get")
  |> Req.Request.prepend_request_steps(test: &TestStep.test_step_correct/1)

response2 = Req.request!(request2)
IO.inspect(response2.status, label: "Status with correct step")
