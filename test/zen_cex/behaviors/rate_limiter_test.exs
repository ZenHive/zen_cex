defmodule ZenCex.Behaviors.RateLimiterTest do
  use ExUnit.Case, async: true

  defmodule TestRateLimiter do
    @behaviour ZenCex.Behaviors.RateLimiter

    def start_link do
      Agent.start_link(fn -> %{count: 0, limit: 10} end, name: __MODULE__)
    end

    @impl true
    def check_and_increment(_endpoint, weight) do
      Agent.get_and_update(__MODULE__, fn state ->
        new_count = state.count + weight

        if new_count > state.limit do
          {{:error, :rate_limited}, state}
        else
          {:ok, %{state | count: new_count}}
        end
      end)
    end

    @impl true
    def update_from_response(_response) do
      :ok
    end

    @impl true
    def get_status(endpoint) do
      state = Agent.get(__MODULE__, & &1)

      %{
        used: state.count,
        limit: state.limit,
        window: 60,
        reset_at: System.system_time(:second) + 60,
        endpoint: endpoint
      }
    end

    @impl true
    def reset(_endpoint) do
      Agent.update(__MODULE__, fn state ->
        %{state | count: 0}
      end)

      :ok
    end

    @impl true
    def get_limits do
      %{
        default: 10,
        window_seconds: 60
      }
    end
  end

  setup do
    {:ok, _pid} = TestRateLimiter.start_link()
    :ok
  end

  describe "rate limiter behavior" do
    test "check_and_increment allows requests within limit" do
      assert :ok = TestRateLimiter.check_and_increment("/api/test", 1)
      assert :ok = TestRateLimiter.check_and_increment("/api/test", 2)

      status = TestRateLimiter.get_status("/api/test")
      assert status.used == 3
      assert status.limit == 10
    end

    test "check_and_increment blocks when limit exceeded" do
      # Use up the limit
      for _ <- 1..10 do
        assert :ok = TestRateLimiter.check_and_increment("/api/test", 1)
      end

      # Next request should be blocked
      assert {:error, :rate_limited} = TestRateLimiter.check_and_increment("/api/test", 1)
    end

    test "check_and_increment respects weight parameter" do
      assert :ok = TestRateLimiter.check_and_increment("/api/heavy", 5)

      status = TestRateLimiter.get_status("/api/heavy")
      assert status.used == 5
    end

    test "reset clears the counter" do
      assert :ok = TestRateLimiter.check_and_increment("/api/test", 5)
      assert TestRateLimiter.get_status(nil).used == 5

      assert :ok = TestRateLimiter.reset(nil)
      assert TestRateLimiter.get_status(nil).used == 0
    end

    test "get_limits returns configuration" do
      limits = TestRateLimiter.get_limits()

      assert limits.default == 10
      assert limits.window_seconds == 60
    end

    test "update_from_response is optional but callable" do
      assert :ok = TestRateLimiter.update_from_response(%{headers: []})
    end
  end

  describe "error formats" do
    test "rate limited error can include retry time" do
      # Fill up the limit
      for _ <- 1..10 do
        TestRateLimiter.check_and_increment("/api/test", 1)
      end

      result = TestRateLimiter.check_and_increment("/api/test", 1)

      # Basic format
      assert {:error, :rate_limited} = result

      # Or with retry time (not implemented in test, but showing the interface)
      # assert {:error, {:rate_limited, 5000}} = result
    end
  end
end
