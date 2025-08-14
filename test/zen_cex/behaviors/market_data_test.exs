defmodule ZenCex.Behaviors.MarketDataTest do
  use ExUnit.Case, async: true

  defmodule TestMarketData do
    use GenServer
    @behaviour ZenCex.Behaviors.MarketData

    @impl ZenCex.Behaviors.MarketData
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl GenServer
    def init(opts) do
      {:ok,
       %{
         status: :disconnected,
         channels: [],
         opts: opts
       }}
    end

    @impl true
    def subscribe(channels) do
      GenServer.call(__MODULE__, {:subscribe, channels})
    end

    @impl true
    def unsubscribe(channels) do
      GenServer.call(__MODULE__, {:unsubscribe, channels})
    end

    @impl true
    def connection_status do
      GenServer.call(__MODULE__, :status)
    end

    @impl true
    def subscribed_channels do
      GenServer.call(__MODULE__, :channels)
    end

    @impl true
    def handle_frame({:text, json}, state) do
      data = Jason.decode!(json)
      {:ok, Map.put(state, :last_message, data)}
    end

    def handle_frame({:binary, _data}, state) do
      {:ok, Map.put(state, :received_binary, true)}
    end

    @impl true
    def websocket_url(:prod), do: "wss://stream.test.com/ws"
    def websocket_url(:test), do: "wss://testnet.test.com/ws"

    @impl true
    def ping_interval, do: 30_000

    # GenServer callbacks
    @impl GenServer
    def handle_call({:subscribe, channels}, _from, state) do
      new_channels = Enum.uniq(state.channels ++ channels)
      {:reply, :ok, %{state | channels: new_channels, status: :connected}}
    end

    def handle_call({:unsubscribe, channels}, _from, state) do
      new_channels = state.channels -- channels
      {:reply, :ok, %{state | channels: new_channels}}
    end

    def handle_call(:status, _from, state) do
      {:reply, state.status, state}
    end

    def handle_call(:channels, _from, state) do
      {:reply, state.channels, state}
    end
  end

  setup do
    start_supervised!(TestMarketData)
    :ok
  end

  describe "market data behavior" do
    test "subscribes to public channels only" do
      channels = ["ticker.BTCUSDT", "trades.ETHUSDT", "depth.BNBUSDT"]

      assert :ok = TestMarketData.subscribe(channels)
      assert channels == TestMarketData.subscribed_channels()
    end

    test "unsubscribes from channels" do
      channels = ["ticker.BTCUSDT", "trades.ETHUSDT"]

      assert :ok = TestMarketData.subscribe(channels)
      assert channels == TestMarketData.subscribed_channels()

      assert :ok = TestMarketData.unsubscribe(["ticker.BTCUSDT"])
      assert ["trades.ETHUSDT"] == TestMarketData.subscribed_channels()
    end

    test "reports connection status" do
      assert :disconnected = TestMarketData.connection_status()

      TestMarketData.subscribe(["ticker.BTCUSDT"])
      assert :connected = TestMarketData.connection_status()
    end

    test "provides WebSocket URLs" do
      assert "wss://stream.test.com/ws" == TestMarketData.websocket_url(:prod)
      assert "wss://testnet.test.com/ws" == TestMarketData.websocket_url(:test)
    end

    test "specifies ping interval" do
      assert 30_000 == TestMarketData.ping_interval()
    end

    test "handles text frames" do
      state = %{channels: []}
      json = Jason.encode!(%{"type" => "ticker", "symbol" => "BTCUSDT"})

      assert {:ok, new_state} = TestMarketData.handle_frame({:text, json}, state)
      assert new_state.last_message["type"] == "ticker"
    end

    test "handles binary frames" do
      state = %{channels: []}

      assert {:ok, new_state} = TestMarketData.handle_frame({:binary, <<1, 2, 3>>}, state)
      assert new_state.received_binary == true
    end
  end

  describe "public channels only" do
    test "no authentication in market data" do
      # This behavior should NOT have any auth-related callbacks
      callbacks = ZenCex.Behaviors.MarketData.behaviour_info(:callbacks)

      auth_related =
        Enum.filter(callbacks, fn {name, _arity} ->
          name in [:authenticate, :login, :get_token, :sign]
        end)

      assert auth_related == []
    end

    test "no user stream methods" do
      callbacks = ZenCex.Behaviors.MarketData.behaviour_info(:callbacks)

      user_related =
        Enum.filter(callbacks, fn {name, _arity} ->
          String.contains?(to_string(name), "user") or
            String.contains?(to_string(name), "private")
        end)

      assert user_related == []
    end
  end
end
