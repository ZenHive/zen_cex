defmodule ZenCex.Core.CircuitBreaker do
  @moduledoc """
  Circuit breaker functionality for ZenCex using req_fuse.

  This module provides per-exchange circuit breaking to prevent cascading failures
  when an exchange becomes unresponsive or returns consistent errors.

  ## Features

  - Per-exchange circuit breakers (not per-endpoint to keep it simple)
  - Configurable thresholds and timeouts
  - Telemetry integration for monitoring
  - Opt-in via configuration
  - Returns 503 Service Unavailable when circuit is open

  ## Configuration

  Circuit breakers are opt-in and can be configured per exchange:

      config :zen_cex, :circuit_breaker,
        enabled: true,
        binance: [
          # Number of failures before opening circuit
          failure_threshold: 5,
          # Time window for failure counting (milliseconds)
          failure_window: 60_000,
          # How long to keep circuit open (milliseconds)
          reset_timeout: 30_000,
          # Optional: custom function to determine if response should blow fuse
          melt_func: &ZenCex.Core.CircuitBreaker.should_blow_fuse?/1
        ]

  ## Telemetry Events

  The circuit breaker emits the following telemetry events:

  - `[:zen_cex, :circuit_breaker, :blown]` - Circuit opened due to failures
  - `[:zen_cex, :circuit_breaker, :reset]` - Circuit closed/reset
  - `[:zen_cex, :circuit_breaker, :rejected]` - Request rejected due to open circuit

  ## Implementation Notes

  We use a simple per-exchange circuit breaker rather than per-endpoint to:
  - Keep complexity low (simplicity principle)
  - Avoid managing hundreds of fuses
  - Provide meaningful protection without over-engineering

  When an exchange's circuit is open, ALL requests to that exchange will be rejected
  with a 503 status until the circuit resets.
  """

  require Logger

  # Default circuit breaker configuration
  @default_failure_threshold 5
  @default_failure_window_ms 60_000
  @default_reset_timeout_ms 30_000

  @doc """
  Attaches circuit breaker to a Req request if enabled in configuration.

  ## Parameters
  - `request` - The Req request to potentially attach circuit breaker to

  ## Returns
  - Modified request with circuit breaker attached if enabled
  - Original request if circuit breaker is disabled or req_fuse not available

  ## Examples

      iex> request = Req.new()
      iex> request = ZenCex.Core.CircuitBreaker.maybe_attach(request, :binance)
  """
  @spec maybe_attach(Req.Request.t(), atom()) :: Req.Request.t()
  def maybe_attach(request, exchange) do
    if enabled?() && Code.ensure_loaded?(ReqFuse) do
      attach_circuit_breaker(request, exchange)
    else
      request
    end
  end

  @doc """
  Checks if circuit breaker is enabled globally.

  ## Returns
  - `true` if circuit breaker is enabled
  - `false` if disabled or not configured
  """
  @spec enabled?() :: boolean()
  def enabled? do
    config = Application.get_env(:zen_cex, :circuit_breaker, [])
    Keyword.get(config, :enabled, false)
  end

  @doc """
  Gets circuit breaker configuration for a specific exchange.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  - Configuration keyword list or empty list if not configured
  """
  @spec get_config(atom()) :: keyword()
  def get_config(exchange) do
    config = Application.get_env(:zen_cex, :circuit_breaker, [])
    Keyword.get(config, exchange, [])
  end

  @doc """
  Default function to determine if a response should blow the fuse.

  This function is used if no custom melt_func is provided in configuration.

  ## Parameters
  - `result` - The request result (either response or exception)

  ## Returns
  - `true` if the fuse should blow (circuit should open)
  - `false` if the fuse should not blow

  ## Logic
  - 5xx errors blow the fuse (server errors)
  - Network errors blow the fuse
  - 429 (rate limit) does NOT blow the fuse
  - 4xx errors (except 429) do NOT blow the fuse (client errors)
  """
  @spec should_blow_fuse?(term()) :: boolean()
  def should_blow_fuse?({:ok, %Req.Response{status: status}}) when status in 500..599 do
    true
  end

  def should_blow_fuse?({:ok, %Req.Response{status: 429}}) do
    # Rate limits should not blow the fuse
    false
  end

  def should_blow_fuse?({:ok, %Req.Response{}}) do
    # Other responses (2xx, 3xx, 4xx except 429) don't blow fuse
    false
  end

  def should_blow_fuse?({:error, %Req.TransportError{}}) do
    # Network errors blow the fuse
    true
  end

  def should_blow_fuse?({:error, %Mint.TransportError{}}) do
    # Mint transport errors blow the fuse
    true
  end

  def should_blow_fuse?({:error, _}) do
    # Other errors don't blow the fuse by default
    false
  end

  def should_blow_fuse?(_) do
    # Unknown result format, don't blow fuse
    false
  end

  # Private functions

  defp attach_circuit_breaker(request, exchange) do
    config = get_config(exchange)

    if config == [] do
      # No configuration for this exchange, skip circuit breaker
      request
    else
      fuse_name = fuse_name(exchange)

      # Initialize the fuse if not already done
      ensure_fuse_installed(fuse_name, config)

      # Attach req_fuse with our configuration
      fuse_opts = build_fuse_opts(fuse_name, config)

      # Attach circuit breaker step
      request
      |> ReqFuse.attach(fuse_opts)
      |> Req.Request.prepend_error_steps([{:zen_cex_circuit_breaker, &handle_blown_fuse/1}])
    end
  end

  defp ensure_fuse_installed(fuse_name, config) do
    # Check if fuse is already installed
    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        # Fuse exists and is ok
        :ok

      :blown ->
        # Fuse exists but is blown
        :ok

      {:error, :not_found} ->
        # Install the fuse with configuration
        failure_threshold = Keyword.get(config, :failure_threshold, @default_failure_threshold)
        failure_window = Keyword.get(config, :failure_window, @default_failure_window_ms)
        reset_timeout = Keyword.get(config, :reset_timeout, @default_reset_timeout_ms)

        # Standard fuse with threshold failures in window, reset after timeout
        fuse_strategy = {
          {:standard, failure_threshold, failure_window},
          {:reset, reset_timeout}
        }

        :ok = :fuse.install(fuse_name, fuse_strategy)
    end
  end

  defp build_fuse_opts(fuse_name, config) do
    # Get custom melt function or use default
    melt_func = Keyword.get(config, :melt_func, &should_blow_fuse?/1)

    [
      fuse_name: fuse_name,
      fuse_mode: :sync,
      fuse_melt_func: melt_func,
      fuse_verbose: false
    ]
  end

  defp fuse_name(exchange) do
    :"zen_cex_fuse_#{exchange}"
  end

  defp handle_blown_fuse({request, {:error, :blown}}) do
    # Extract exchange from request
    exchange = request.options[:exchange]

    # Get reset timeout from config for accurate retry-after header
    config = get_config(exchange)
    reset_timeout_ms = Keyword.get(config, :reset_timeout, @default_reset_timeout_ms)
    retry_after_seconds = div(reset_timeout_ms, 1000)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :circuit_breaker, :rejected],
      %{count: 1},
      %{exchange: exchange}
    )

    # Return 503 Service Unavailable
    response = %Req.Response{
      status: 503,
      body: "Service temporarily unavailable - circuit breaker open for #{exchange}",
      headers: [
        {"retry-after", Integer.to_string(retry_after_seconds)}
      ]
    }

    {request, response}
  end

  defp handle_blown_fuse({request, error}) do
    # Not a blown fuse error, pass through
    {request, error}
  end

  @doc """
  Manually resets the circuit breaker for an exchange.

  This can be used for manual intervention or testing.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  - `:ok` if reset successful
  - `{:error, reason}` if reset failed
  """
  @spec reset(atom()) :: :ok | {:error, term()}
  def reset(exchange) do
    fuse_name = fuse_name(exchange)

    case :fuse.reset(fuse_name) do
      :ok ->
        :telemetry.execute(
          [:zen_cex, :circuit_breaker, :reset],
          %{count: 1},
          %{exchange: exchange, manual: true}
        )

        :ok

      error ->
        error
    end
  end

  @doc """
  Checks the current state of a circuit breaker.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  - `:ok` if circuit is closed (normal operation)
  - `:blown` if circuit is open (rejecting requests)
  - `{:error, :not_found}` if no circuit breaker for this exchange
  """
  @spec status(atom()) :: :ok | :blown | {:error, :not_found}
  def status(exchange) do
    fuse_name = fuse_name(exchange)
    :fuse.ask(fuse_name, :sync)
  end
end
