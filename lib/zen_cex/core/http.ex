defmodule ZenCex.Core.HTTP do
  @moduledoc """
  Thin REQ coordinator. Adapters handle specifics.
  """

  def base_request(exchange, operation_type \\ :standard) do
    adapter = ZenCex.Core.Registry.get_adapter!(exchange)

    receive_timeout =
      case operation_type do
        :trading -> 2_000
        :market -> 5_000
        :historical -> 30_000
        _ -> 5_000
      end

    Req.new()
    |> Req.Request.register_options([:exchange, :operation_type])
    |> Req.merge(
      base_url: adapter.base_url(:prod),
      finch: ZenCex.Finch,
      retry: :safe_transient,
      retry_delay: &exponential_backoff_with_jitter/1,
      max_retries: 3,
      receive_timeout: receive_timeout,
      exchange: exchange,
      operation_type: operation_type
    )
  end

  defp exponential_backoff_with_jitter(n) do
    base_ms = min(1000 * 2 ** min(n, 10), 60_000)
    jitter_ms = :rand.uniform(500)
    min(base_ms + jitter_ms, 60_000)
  end
end
