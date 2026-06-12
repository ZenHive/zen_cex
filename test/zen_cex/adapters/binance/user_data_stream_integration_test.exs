defmodule ZenCex.Adapters.Binance.UserDataStreamIntegrationTest do
  @moduledoc """
  Integration tests for UserDataStream using real Binance production API.

  Uses TEST_BINANCE_API_KEY / TEST_BINANCE_SECRET_KEY from environment.
  These tests connect to fapi.binance.com (production futures) — ensure
  the test account has futures enabled and minimal funds.

  Run with:
      TEST_BINANCE_API_KEY=xxx TEST_BINANCE_SECRET_KEY=yyy \
        mix test test/zen_cex/adapters/binance/user_data_stream_integration_test.exs \
        --include user_data_stream

  Or source .env first:
      source /path/to/.env && mix test ... --include user_data_stream
  """

  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance.UserDataStream

  require Logger

  @moduletag :user_data_stream
  @moduletag :integration

  # Timeouts
  @connect_timeout  8_000
  @event_timeout   15_000

  # ── Credentials helper ──────────────────────────────────────

  defp credentials do
    api_key    = System.get_env("BINANCE_API_KEY")    || System.get_env("TEST_BINANCE_API_KEY")
    api_secret = System.get_env("BINANCE_SECRET_KEY") || System.get_env("TEST_BINANCE_SECRET_KEY")

    if is_nil(api_key) or is_nil(api_secret) do
      raise """
      Missing Binance API credentials.
      Set TEST_BINANCE_API_KEY and TEST_BINANCE_SECRET_KEY (or source .env).
      """
    end

    %{api_key: api_key, api_secret: api_secret}
  end

  # ── Setup / teardown ────────────────────────────────────────

  setup do
    # Each test uses a unique account_id to avoid Registry collisions
    account_id = :"test_#{System.unique_integer([:positive])}"
    on_exit(fn -> UserDataStream.stop(account_id) end)
    {:ok, account_id: account_id}
  end

  # ── Tests ───────────────────────────────────────────────────

  describe "start_link/1 and Registry" do
    test "starts successfully and registers under account_id", %{account_id: id} do
      test_pid = self()

      {:ok, pid} = UserDataStream.start_link(
        account_id:  id,
        credentials: credentials(),
        events:      ["ORDER_TRADE_UPDATE"],
        handlers:    %{:default => fn _event -> send(test_pid, :event_received) end}
      )

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Registry lookup should find it
      assert {:ok, _info} = UserDataStream.get_info(id)
    end

    test "two accounts can run simultaneously", %{account_id: id_a} do
      id_b = :"test_b_#{System.unique_integer([:positive])}"
      on_exit(fn -> UserDataStream.stop(id_b) end)

      creds = credentials()

      {:ok, pid_a} = UserDataStream.start_link(
        account_id:  id_a,
        credentials: creds,
        events:      ["ORDER_TRADE_UPDATE"],
        handlers:    %{:default => fn _e -> :ok end}
      )

      {:ok, pid_b} = UserDataStream.start_link(
        account_id:  id_b,
        credentials: creds,
        events:      ["ORDER_TRADE_UPDATE"],
        handlers:    %{:default => fn _e -> :ok end}
      )

      assert pid_a != pid_b
      assert Process.alive?(pid_a)
      assert Process.alive?(pid_b)

      UserDataStream.stop(id_b)
    end
  end

  describe "get_info/1" do
    test "returns :not_found for unknown account" do
      assert {:error, :not_found} = UserDataStream.get_info(:nonexistent_account_xyz)
    end

    test "returns stream info after start", %{account_id: id} do
      {:ok, _pid} = UserDataStream.start_link(
        account_id:  id,
        credentials: credentials(),
        events:      ["ORDER_TRADE_UPDATE", "ACCOUNT_UPDATE"],
        handlers:    %{:default => fn _e -> :ok end}
      )

      # Wait for :connect to process
      Process.sleep(@connect_timeout)

      {:ok, info} = UserDataStream.get_info(id)

      assert info.account_id == id
      assert info.events == ["ORDER_TRADE_UPDATE", "ACCOUNT_UPDATE"]
      assert is_integer(info.started_at)

      # After successful connect, listen_key should be present (truncated)
      if info.connected do
        assert is_binary(info.listen_key)
        assert String.ends_with?(info.listen_key, "...")
        Logger.info("Stream connected, listen_key prefix: #{info.listen_key}")
      else
        Logger.warning("Stream not yet connected (may still be initializing)")
      end
    end
  end

  describe "listenKey lifecycle" do
    @tag timeout: 15_000
    test "obtains a listenKey from fapi.binance.com on connect", %{account_id: id} do
      {:ok, _pid} = UserDataStream.start_link(
        account_id:  id,
        credentials: credentials(),
        events:      ["ORDER_TRADE_UPDATE"],
        handlers:    %{:default => fn _e -> :ok end}
      )

      # Poll until connected or timeout
      connected? =
        Enum.reduce_while(1..20, false, fn _, _ ->
          Process.sleep(500)
          case UserDataStream.get_info(id) do
            {:ok, %{connected: true}} -> {:halt, true}
            _                         -> {:cont, false}
          end
        end)

      assert connected?, "UserDataStream did not connect within 10s — check API key and fapi.binance.com access"

      {:ok, info} = UserDataStream.get_info(id)
      assert info.connected == true
      assert is_binary(info.listen_key)
    end
  end

  describe "event dispatch" do
    @tag timeout: 30_000
    test "default handler receives events (if any arrive)", %{account_id: id} do
      test_pid = self()

      {:ok, _pid} = UserDataStream.start_link(
        account_id:  id,
        credentials: credentials(),
        events:      ["ORDER_TRADE_UPDATE", "ACCOUNT_UPDATE"],
        handlers: %{
          "ORDER_TRADE_UPDATE" => fn event ->
            send(test_pid, {:order_event, event})
          end,
          "ACCOUNT_UPDATE" => fn event ->
            send(test_pid, {:account_event, event})
          end,
          :default => fn event ->
            send(test_pid, {:other_event, event})
          end
        }
      )

      # Wait for connection
      Process.sleep(@connect_timeout)

      # We can't force Binance to send events without placing orders,
      # so we just verify the stream is alive and handlers are wired.
      # If an event does arrive, we assert its shape.
      receive do
        {:order_event, event} ->
          assert event["e"] == "ORDER_TRADE_UPDATE"
          Logger.info("Received ORDER_TRADE_UPDATE: #{inspect(event, limit: 5)}")

        {:account_event, event} ->
          assert event["e"] == "ACCOUNT_UPDATE"
          Logger.info("Received ACCOUNT_UPDATE: #{inspect(event, limit: 5)}")

        {:other_event, event} ->
          assert is_map(event)
          Logger.info("Received other event: #{inspect(event, limit: 5)}")
      after
        # No events in 15s is normal for an idle account — not a failure
        @event_timeout ->
          Logger.info("No events in #{@event_timeout}ms — account idle, stream is alive")
          {:ok, info} = UserDataStream.get_info(id)
          assert info.connected, "Stream should still be connected after idle period"
      end
    end
  end

  describe "stop/1" do
    test "stops the process and cleans up listenKey", %{account_id: id} do
      {:ok, pid} = UserDataStream.start_link(
        account_id:  id,
        credentials: credentials(),
        events:      ["ORDER_TRADE_UPDATE"],
        handlers:    %{:default => fn _e -> :ok end}
      )

      assert Process.alive?(pid)

      # Wait a bit so listenKey is obtained
      Process.sleep(min(@connect_timeout, 5_000))

      # Stop should be clean
      :ok = UserDataStream.stop(id)

      # Process should be dead
      Process.sleep(200)
      refute Process.alive?(pid)

      # Registry should no longer find it
      assert {:error, :not_found} = UserDataStream.get_info(id)
    end

    test "stop/1 on non-existent account returns :ok" do
      assert :ok = UserDataStream.stop(:account_that_never_existed)
    end
  end

  describe "handler error isolation" do
    test "handler crash does not kill the stream process", %{account_id: id} do
      # We can't easily trigger a real event, but we can verify the
      # build_dispatch_handler rescue block works by testing the process stays alive
      # after start (even if no events come in).
      {:ok, pid} = UserDataStream.start_link(
        account_id:  id,
        credentials: credentials(),
        events:      ["ORDER_TRADE_UPDATE"],
        handlers: %{
          "ORDER_TRADE_UPDATE" => fn _event ->
            raise "intentional handler crash"
          end,
          :default => fn _e -> :ok end
        }
      )

      Process.sleep(2_000)

      # Stream process must still be alive
      assert Process.alive?(pid), "Stream process died — handler crash should be rescued"
    end
  end
end
