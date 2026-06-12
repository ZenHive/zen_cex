# Binance WebSocket 2026 新架构使用指南

> 适用版本:zen_cex `fix/binance-2026-ws-architecture` 分支(commit `3a6cf0a`)

## 背景

2026 年 4 月 23 日,Binance 对 Futures WebSocket 端点进行了重大架构调整,将原来统一的 `/ws/<stream>` 和 `/stream?streams=` 拆分为三条独立通道,并废弃旧端点.本文档说明新架构的连接方式及 zen_cex 的使用方法.

---

## 新架构概览

| 通道 | 端点 | 用途 | 典型 stream |
|------|------|------|-------------|
| `futures_public` | `wss://fstream.binance.com/public/ws/<stream>` | 高频公共数据 | `depth20@100ms`, `bookTicker` |
| `futures_market` | `wss://fstream.binance.com/market/ws/<stream>` | 行情数据 | `kline_1m`, `markPrice`, `aggTrade` |
| `futures_private` | `wss://fstream.binance.com/private/ws?listenKey=<lk>&events=<EVENT>` | 用户私有数据(单事件) | `ORDER_TRADE_UPDATE` |
| `futures_private` | `wss://fstream.binance.com/private/stream?streams=<lk>@E1/<lk>@E2` | 用户私有数据(多事件) | `ORDER_TRADE_UPDATE` + `ACCOUNT_UPDATE` |

> **旧端点已废弃**:`wss://fstream.binance.com/ws/<stream>` 和 `/stream?streams=` 不再可用.

---

## 快速开始

### 1. 行情数据(kline / markPrice / aggTrade)

```elixir
alias ZenCex.Adapters.Binance.WebSocket

# 订阅 BTCUSDT 1 分钟 K 线
{:ok, conn} = WebSocket.connect(
  ["btcusdt@kline_1m"],
  market: :futures_market
)

# 等待数据写入 ETS(约 1-2 秒)
Process.sleep(2000)

# 从 ETS 读取缓存数据
{:ok, data} = ZenCex.Cache.Market.get_market_data(:binance, "BTCUSDT", "kline_1m")
IO.inspect(data["close"])   # => "61800.00"

WebSocket.close(conn)
```

### 2. 高频公共数据(orderbook depth)

```elixir
# 订阅 20 档深度,100ms 推送
{:ok, conn} = WebSocket.connect(
  ["btcusdt@depth20@100ms"],
  market: :futures_public
)

Process.sleep(1000)

{:ok, book} = ZenCex.Cache.Market.get_market_data(:binance, "BTCUSDT", "depth20")
IO.puts("Best bid: #{hd(book["bids"])["price"]}")
IO.puts("Best ask: #{hd(book["asks"])["price"]}")

WebSocket.close(conn)
```

### 3. 私有用户数据流(单事件)

```elixir
# 第一步:获取 listenKey(需要 API Key)
{:ok, listen_key} = create_listen_key(api_key, api_secret)

# 第二步:连接私有流,只订阅订单更新
{:ok, conn} = WebSocket.connect(
  [],
  market: :futures_private,
  listen_key: listen_key,
  events: ["ORDER_TRADE_UPDATE"]
)

# 第三步:下单触发事件
# ...

# 从 ETS 读取订单更新
{:ok, event} = ZenCex.Cache.Market.get_market_data(:binance, "BTCUSDT", "ORDER_TRADE_UPDATE")
IO.inspect(event["o"]["X"])  # 订单状态,如 "NEW" / "FILLED"

WebSocket.close(conn)
```

### 4. 私有用户数据流(多事件)

```elixir
# 同时订阅多个事件,使用 stream 模式(/private/stream?streams=...)
{:ok, conn} = WebSocket.connect(
  [],
  market: :futures_private,
  listen_key: listen_key,
  events: ["ORDER_TRADE_UPDATE", "ACCOUNT_UPDATE"]
)
```

> **注意**:多事件模式下 Binance 返回 stream wrapper 格式:
> ```json
> {"stream": "<listenKey>@ORDER_TRADE_UPDATE", "data": {"e": "ORDER_TRADE_UPDATE", ...}}
> ```
> zen_cex 会自动解包,user handler 和 ETS 缓存均收到内层 event map.

### 5. 自定义 user handler

```elixir
my_handler = fn
  {:message, %{"e" => "ORDER_TRADE_UPDATE", "o" => order} = _event} ->
    IO.puts("Order #{order["i"]} status: #{order["X"]}")
  {:message, %{"e" => "ACCOUNT_UPDATE"} = event} ->
    IO.puts("Account update: #{inspect(event["a"])}")
  _ ->
    :ok
end

{:ok, conn} = WebSocket.connect(
  [],
  market: :futures_private,
  listen_key: listen_key,
  events: ["ORDER_TRADE_UPDATE", "ACCOUNT_UPDATE"],
  handler: my_handler
)
```

---

## ETS 缓存键说明

所有数据通过 `ZenCex.Cache.Market.get_market_data/3` 读取:

```elixir
ZenCex.Cache.Market.get_market_data(:binance, symbol, event_type)
```

| `event_type` | `symbol` | 说明 |
|---|---|---|
| `"kline_1m"` | `"BTCUSDT"` | 1 分钟 K 线 |
| `"kline_5m"` | `"BTCUSDT"` | 5 分钟 K 线 |
| `"markPriceUpdate"` | `"BTCUSDT"` | 标记价格(注意是 `markPriceUpdate`,不是 `markPrice`) |
| `"depth20"` | `"BTCUSDT"` | 20 档深度 |
| `"trade"` | `"BTCUSDT"` | 最新成交 |
| `"ORDER_TRADE_UPDATE"` | `"BTCUSDT"` | 订单更新(私有流) |
| `"ACCOUNT_UPDATE"` | `"_account"` | 账户余额/仓位变化(私有流,无 symbol) |

---

## listenKey 管理

listenKey 有效期 **30 分钟**,需要定期续期:

```elixir
# 获取 listenKey(POST /fapi/v1/listenKey)
defp create_listen_key(api_key, api_secret) do
  qs = "timestamp=#{:os.system_time(:millisecond)}&recvWindow=5000"
  sig = :crypto.mac(:hmac, :sha256, api_secret, qs) |> Base.encode16(case: :lower)
  url = "https://fapi.binance.com/fapi/v1/listenKey?#{qs}&signature=#{sig}"
  headers = [{"X-MBX-APIKEY", api_key}, {"content-type", "application/x-www-form-urlencoded"}]
  {:ok, {{_, 200, _}, _, body}} = :httpc.request(:post, {url, headers, "", ""}, [], [])
  {:ok, Jason.decode!(body)["listenKey"]}
end

# 续期 listenKey(PUT /fapi/v1/listenKey,每 20 分钟调用一次)
defp keepalive_listen_key(api_key, listen_key) do
  # PUT /fapi/v1/listenKey?listenKey=<key>
  # ...
end
```

> zen_cex 目前不自动续期 listenKey,需要应用层自行管理(建议每 20 分钟 keepalive 一次).

---

## 合法的私有流事件类型

| 事件 | 触发条件 |
|------|---------|
| `ORDER_TRADE_UPDATE` | 订单状态变化(下单、成交、撤单) |
| `ACCOUNT_UPDATE` | 余额或仓位变化(成交后、入金等) |
| `ACCOUNT_CONFIG_UPDATE` | 账户配置变化(杠杆倍数等) |
| `MARGIN_CALL` | 保证金不足预警 |

> **注意**:GTC 限价单挂单**不会**触发 `ACCOUNT_UPDATE`(余额未实际变化).只有成交后才会触发.

---

## 常见问题

**Q: markPrice 数据读不到?**
A: Binance 推送的事件类型是 `markPriceUpdate`,不是 `markPrice`.ETS key 应使用 `"markPriceUpdate"`.

**Q: user handler 里收不到 ORDER_TRADE_UPDATE?**
A: 确认使用的是 `fix/binance-2026-ws-architecture` 分支(commit `3a6cf0a` 以上).旧版 `wrap_handler` 传给 user handler 的是 stream wrapper(无 `"e"` key),已修复.

**Q: 多事件流连接后 user handler 匹配不到事件?**
A: 多事件流响应是 `{"stream": "...", "data": {...}}`,zen_cex 会自动解包,user handler 收到的是内层 `{"e": "ORDER_TRADE_UPDATE", ...}`,直接匹配 `"e"` key 即可.

**Q: 下单报 `-2019 Margin is insufficient`?**
A: 检查是否有残留未撤销的订单占用保证金:
```elixir
{:ok, orders} = UsdmFutures.get_open_orders(%{symbol: "BTCUSDT"}, opts)
# 逐一撤销或使用 cancel_all_open_orders
```

---

## 相关文件

- `lib/zen_cex/adapters/binance/websocket.ex` — WebSocket 适配器实现
- `scripts/test_ws_full.exs` — 10 项集成测试(含真实下单验证私有流)
- `CHANGELOG.md` — 本次变更详情
