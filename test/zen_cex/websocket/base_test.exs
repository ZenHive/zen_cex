defmodule ZenCex.WebSocket.BaseTest do
  @moduledoc """
  Tests for the WebSocket Base behavior module.

  This module tests the behavior definition and ensures all required
  callbacks are properly defined. It also provides a mock implementation
  for testing purposes.
  """

  use ExUnit.Case, async: true

  alias ZenCex.WebSocket.Base

  describe "behavior definition" do
    test "defines required callbacks" do
      # Verify the behavior defines all required callbacks
      callbacks = Base.behaviour_info(:callbacks)

      assert {:connect, 1} in callbacks
      assert {:subscribe, 2} in callbacks
      assert {:unsubscribe, 2} in callbacks
      assert {:state, 1} in callbacks
      assert {:close, 1} in callbacks
    end

    test "callback arities are correct" do
      callbacks = Base.behaviour_info(:callbacks)

      # Map to make lookup easier
      callback_map = Map.new(callbacks)

      assert callback_map[:connect] == 1
      assert callback_map[:subscribe] == 2
      assert callback_map[:unsubscribe] == 2
      assert callback_map[:state] == 1
      assert callback_map[:close] == 1
    end
  end

  describe "mock implementation" do
    defmodule MockWebSocket do
      @behaviour Base

      @impl true
      def connect(opts) do
        if Keyword.get(opts, :fail) do
          {:error, :mock_connection_failed}
        else
          {:ok, self()}
        end
      end

      @impl true
      def subscribe(connection, streams) do
        if is_pid(connection) and is_list(streams) do
          :ok
        else
          {:error, :invalid_params}
        end
      end

      @impl true
      def unsubscribe(connection, streams) do
        if is_pid(connection) and is_list(streams) do
          :ok
        else
          {:error, :invalid_params}
        end
      end

      @impl true
      def state(connection) do
        if is_pid(connection) do
          {:ok, %{status: :connected, streams: []}}
        else
          {:error, :invalid_connection}
        end
      end

      @impl true
      def close(connection) do
        if is_pid(connection) do
          :ok
        else
          {:error, :invalid_connection}
        end
      end
    end

    test "mock implementation satisfies behavior" do
      # This will compile-time verify that MockWebSocket implements all callbacks
      assert {:ok, pid} = MockWebSocket.connect([])
      assert is_pid(pid)

      assert :ok = MockWebSocket.subscribe(pid, ["test_stream"])
      assert :ok = MockWebSocket.unsubscribe(pid, ["test_stream"])
      assert {:ok, state} = MockWebSocket.state(pid)
      assert is_map(state)
      assert :ok = MockWebSocket.close(pid)
    end

    test "mock implementation handles errors" do
      assert {:error, :mock_connection_failed} = MockWebSocket.connect(fail: true)
      assert {:error, :invalid_params} = MockWebSocket.subscribe(nil, ["stream"])
      assert {:error, :invalid_params} = MockWebSocket.subscribe(self(), nil)
      assert {:error, :invalid_connection} = MockWebSocket.state(nil)
      assert {:error, :invalid_connection} = MockWebSocket.close(nil)
    end
  end
end
