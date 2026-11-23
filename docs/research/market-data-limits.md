# Market Data Limits: Binance Spot & Yahoo Finance (`v8/finance/chart`)

> Research ticket: [itsnang/Trading-Lab#3](https://github.com/itsnang/Trading-Lab/issues/3) · Parent Map: [#2](https://github.com/itsnang/Trading-Lab/issues/2)  
> Verified against Binance official Spot API documentation (`binance/binance-spot-api-docs`), live responses from `data-api.binance.vision` / `api.binance.com` / `query1.finance.yahoo.com`, `ranaroussi/yfinance` source, and Apple `URLSessionWebSocketTask` documentation.

---

## Executive Decision Gist

- **Binance REST (`data-api.binance.vision`)**: Hard cap of **1,000 bars/request** (`weight = 2` against a **6,000 weight/min** per-IP budget that is **shared** with `api.binance.com`); paginate backward with `endTime = firstOpenTimeMs - 1` and never fail over to `api.binance.com` on `429`.
- **Binance WebSocket (`data-stream.binance.vision`)**: Hard **24h connection lifetime**, server `ping` every **20s** (1m pong deadline), max **1,024 streams**, **5 incoming msg/s**, **300 connects / 5m / IP**; rotate proactively at **23h45m** or on `!serverShutdown`, use jittered exponential backoff (`1s → 60s`), and REST gap-fill on reconnect.
- **Yahoo Finance (`v8/finance/chart`)**: Intraday retention is strictly capped by interval — **`1m`: 8d/request within last 30d** (stitchable via `period1`/`period2`), **`5m`/`15m`/`30m`: 60d** (1 call), **`60m`: 730d** (1 call), **`1d`: full history via `period1`/`period2`** (avoid `range=max`, which silently downgrades `1d` to `1mo`). Fetch deep history once into cache and poll only a narrow tail window (`range=1d` or last few bars), pausing during closed market sessions to avoid `HTTP 429`.

---

## Current MSNR Desk Baseline

Inspected in `TradingLab/Sources/TradingLab/Engine/LiveMarketService.swift`, `WorkspaceStore.swift`, and `Models/MarketModels.swift`:

- **Instruments**: Binance (`PAXGUSDT`, `BTCUSDT`, `ETHUSDT`) with Yahoo fallback; Yahoo-only (`GC=F`, `EURUSD=X`, `YM=F`, `NQ=F`).
- **Historical fetch**: Single unpaginated call capped at `260` bars (`limit=260` on Binance; Yahoo `range` of `1d`/`5d`/`1mo`/`3mo`/`1y`, then `.suffix(260)`).
- **Binance WS**: Connects to `wss://data-stream.binance.vision/stream?streams=<sym>@kline_<tf>/<sym>@aggTrade` via `URLSessionWebSocketTask`. No automatic reconnect, no `!serverShutdown` handling, no client liveness watchdog, and no REST gap-fill after drops.
- **Yahoo live updates**: Polls the entire historical `range` every `10s` (`Timer.scheduledTimer(withTimeInterval: 10.0)`), even on higher timeframes (`H1`/`H4`/`D1`) and even when `marketStatus().isOpen == false`, failing over `query1 → query2` without `429` backoff.

---

## 1. Binance Spot Public REST (`/api/v3/klines`)

### 1.1 Parameters, Caps & Pagination

| Property | Verified Specification | Source |
| :--- | :--- | :--- |
| Endpoint | `GET /api/v3/klines` (and `GET /api/v3/uiKlines`, identical limits) | [Binance `rest-api.md` §klines](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#klinecandlestick-data) |
| Per-request bar cap (`limit`) | Default `500`; **maximum `1000`**. Passing `limit > 1000` (e.g. `1500`) silently clamps to `1000` rows. | [Binance `rest-api.md` §klines](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#klinecandlestick-data) + live probe |
| Supported intervals | `1s`, `1m`, `3m`, `5m`, `15m`, `30m`, `1h`, `2h`, `4h`, `6h`, `8h`, `12h`, `1d`, `3d`, `1w`, `1M` | [Binance `rest-api.md` §kline-intervals](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#kline-intervals) |
| Ordering & timestamp units | Chronological (oldest → newest). Milliseconds by default (`startTime`/`endTime` always interpreted in UTC, even when `timeZone` is set). | [Binance `rest-api.md` §General](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#general-api-information) |
| Data source | `Database` (asynchronous replication; minor lag possible vs WS) | [Binance `rest-api.md` §klines](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#klinecandlestick-data) |

**Exact `startTime` / `endTime` semantics** ([`rest-api.md`](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#general-api-information)):
- Neither sent: returns the most recent candles up to `limit`.
- `startTime` only: returns the oldest candles starting at `startTime` (inclusive) up to `limit`.
- `endTime` only: returns the most recent candles ending at `endTime` (inclusive) up to `limit`.
- Both sent: returns candles forward from `startTime`, stopping at `endTime` or `limit`.

**Backward pagination rule (verified live)**: Because `endTime` is **inclusive** of candle open time, passing `endTime = earliestBar.openTimeMs` duplicates the boundary candle. Step backward with:
```text
nextEndTime = earliestBar.openTimeMs - 1
```
Stop when a page returns `< limit` rows (or `0` rows) or reaches the target bar count.

### 1.2 Request Weight & IP Rate Limits

Verified against [`rest-api.md` §LIMITS](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md#limits) and live `GET https://data-api.binance.vision/api/v3/exchangeInfo?symbol=BTCUSDT`:

| Limit Type | Interval | Limit | Notes |
| :--- | :--- | :--- | :--- |
| `/api/v3/klines` weight | per request | **2** | Charged identically for `limit=1` or `limit=1000` (always request `1000` when paginating). |
| `REQUEST_WEIGHT` | 1 minute | **6,000** | Per IP (not per API key). Reported on every response via `X-MBX-USED-WEIGHT-1M`. |
| `RAW_REQUESTS` | 5 minutes | **300,000** | Per IP. |
| Rate-limit violation | — | **HTTP 429** | Includes `Retry-After` (seconds). Client **must** back off immediately. |
| Auto IP ban | — | **HTTP 418** | Triggered by ignoring `429`. Escalates from **2 minutes to 3 days**; includes `Retry-After`. |
| WAF violation | — | **HTTP 403** | Web Application Firewall block (rate/security/SQL keyword rule). |

At weight `2` per `1,000`-bar request, the theoretical ceiling is `3,000` kline requests/min (`3,000,000` bars/min). In practice, stay well under **50% of `X-MBX-USED-WEIGHT-1M`** (e.g., pause if `X-MBX-USED-WEIGHT-1M > 3000`).

### 1.3 `data-api.binance.vision` vs `api.binance.com`

| Dimension | `data-api.binance.vision` | `api.binance.com` |
| :--- | :--- | :--- |
| Scope | **Public market data only** (13 endpoints: `klines`, `uiKlines`, `aggTrades`, `trades`, `depth`, `ticker/*`, `avgPrice`, `exchangeInfo`, `ping`, `time`). No API keys or account/order routes. ([`market_data_only.md`](https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md)) | Full Spot REST API (public + signed trading/account endpoints). |
| Rate limits | Identical (`6,000` weight/1m; `300,000` raw/5m). | Identical (`6,000` weight/1m; `300,000` raw/5m). |
| IP weight bucket | **Shared with `api.binance.com`**. Live test alternating `vision → api → vision` incremented `X-MBX-USED-WEIGHT-1M` monotonically (`2 → 4 → 6`). | Shared with `data-api.binance.vision`. |
| Geo-restrictions (`HTTP 451`) | Enforced by IP compliance/CDN on both domains. Switching domains does **not** bypass `451`. | Enforced. |

**Implementation implication**: Keep `data-api.binance.vision` as primary. Only fail over to `api.binance.com` on network/DNS/`5xx` errors — **never** on `429`, `418`, or `451` (failing over on `429` burns the same IP quota and accelerates a `418` IP ban).

---

## 2. Binance WebSocket Streams (`wss://data-stream.binance.vision`)

All specifications verified verbatim from [Binance `web-socket-streams.md`](https://github.com/binance/binance-spot-api-docs/blob/master/web-socket-streams.md) and [`faqs/market_data_only.md`](https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md):

| Constraint | Exact Limit / Behavior |
| :--- | :--- |
| Base endpoint | `wss://data-stream.binance.vision` (port `443`; market data only, no User Data Streams). |
| URL formats | Raw: `/ws/<stream>` · Combined: `/stream?streams=<s1>/<s2>` (lowercase symbols). |
| **Connection lifetime** | **24 hours max**. Server disconnects unconditionally at the 24h mark. |
| **Graceful shutdown event** | Server sends `serverShutdown` before planned teardown (combined wrapper: `{"stream":"!serverShutdown","data":{"e":"serverShutdown","E":<ms>,"T":<shutdownMs>}}`). Open a replacement socket immediately before `T`. |
| **Server ping/pong cadence** | Server sends an RFC 6455 `ping` frame every **20 seconds**. Client must reply with a `pong` frame echoing the exact ping payload within **1 minute**, or the server disconnects. Unsolicited `pong` frames (empty payload recommended) are allowed but do **not** satisfy an unanswered server ping. |
| **Max streams / connection** | **1,024 streams** per WebSocket connection. |
| **Incoming message rate limit** | **5 incoming messages / second** per connection (counts `PING`, `PONG`, and JSON `SUBSCRIBE`/`UNSUBSCRIBE`). Exceeding causes disconnect; repeat offenders may be IP-banned. |
| **Connection attempt rate limit** | **300 connection attempts per 5 minutes per IP** (~1/s average). |

### `URLSessionWebSocketTask` Keepalive & Recommended Reconnect Policy

1. **Pong handling**: Apple's `URLSessionWebSocketTask` implements RFC 6455 control framing and automatically replies to server-initiated `ping` frames with matching `pong` frames ([Apple `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)). However, it does **not** detect silent half-open TCP drops on its own — run a client-side `sendPing` watchdog every **30–45s** (only `0.02–0.03 msg/s`, negligible vs the `5 msg/s` cap) and cancel/reconnect if `sendPing` errors or times out in `10s`.
2. **Proactive rotation**: Schedule a clean blue/green reconnect at **23h 45m** (15 minutes before the 24h cutoff), and trigger immediate blue/green reconnect whenever `stream == "!serverShutdown"` arrives.
3. **Exponential backoff with jitter** (on unexpected drops):
   - Delay schedule: `min(60s, 1s * 2^attempt) + uniform(0, 0.25 * delay)` → `~1s, 2s, 4s, 8s, 16s, 32s, 60s…`
   - Worst-case attempts in 5 minutes: **≤ 9 attempts** (vs the `300 / 5 min / IP` limit, leaving 97% headroom even across multiple tabs/charts).
   - Reset `attempt = 0` only after the socket stays connected for ≥ `30s` (or delivers a valid market event), preventing tight crash loops from hitting the 300/5m cap.
4. **Post-reconnect gap-fill**: On every reconnect (and after macOS sleep/wake), issue a single REST `/api/v3/klines` request with `startTime = lastCandle.openTimeMs` (`limit = 1000`) to patch any missed bars during downtime.
5. **Multiplexing**: A single combined connection easily handles all 3 Binance instruments × 7 timeframes + `aggTrade` (`24` streams total vs `1,024` max). Use `SUBSCRIBE`/`UNSUBSCRIBE` (batched in one JSON message, staying well under `5 msg/s`) instead of tearing down and reopening sockets on every timeframe click.

---

## 3. Yahoo Finance `v8/finance/chart` (`query1` / `query2.finance.yahoo.com`)

Yahoo Finance does **not** publish official API documentation; limits below were verified directly via live HTTP `200`/`422` probes against `query1.finance.yahoo.com/v8/finance/chart` for MSNR Desk tickers (`GC=F`, `EURUSD=X`, `YM=F`, `NQ=F`) and cross-checked against [`ranaroussi/yfinance` `history.py`](https://github.com/ranaroussi/yfinance/blob/main/yfinance/scrapers/history.py).

### 3.1 Intraday Retention & Per-Request Caps

| Interval | Per-Request Span Cap | Max Rolling Lookback | Verified Live Bar Count (`GC=F` / `EURUSD=X`) | Verbatim First-Party HTTP 422 Server Error |
| :--- | :--- | :--- | :--- | :--- |
| **`1m`** | **8 days** | **30 days** | 8d single call: `8,630–8,980` bars; 30d stitched (4 calls): `~25k–34k` bars | `Only 8 days worth of 1m granularity data are allowed to be fetched per request.` / `The requested range must be within the last 30 days.` |
| **`5m`** | 60 days (1 call) | **60 days** | 59d call: `14,400` (`GC=F`, `YM=F`) / `11,798` (`EURUSD=X`) | `5m data not available for startTime=... The requested range must be within the last 60 days.` |
| **`15m`** | 60 days (1 call) | **60 days** | 59d call: `4,801` (`GC=F`) / `3,934` (`EURUSD=X`) | `15m data not available for startTime=... The requested range must be within the last 60 days.` |
| **`30m`** | 60 days (1 call) | **60 days** | 59d call: `2,401` (`GC=F`) / `1,968` (`EURUSD=X`) | `30m data not available for startTime=... The requested range must be within the last 60 days.` *(See note below)* |
| **`60m` / `1h`** | 730 days (1 call) | **730 days (~2y)** | 729d call: `14,480` (`GC=F`, `NQ=F`) / `12,487` (`EURUSD=X`) | `1h data not available for startTime=... The requested range must be within the last 730 days.` |
| **`1d`** | Full history (1 call via `period1`/`period2`) | Full ticker history | 20y `period1`/`period2`: `5,038` bars (`GC=F`); `range=10y`: `2,518` bars | *(No 422; see `range=max` downgrade gotcha below)* |

> **Critical Yahoo API Gotchas (Verified Live)**:
> 1. **`interval=1d&range=max` silently downgrades granularity to `1mo`**: Probing `GC=F` and `EURUSD=X` with `interval=1d&range=max` returned `meta.dataGranularity = "1mo"` (`269` / `277` monthly bars) instead of daily bars! Always pass explicit `period1` & `period2` (or `range=5y`/`10y`) and assert `meta.dataGranularity` matches the requested interval.
> 2. **`30m` interval quirk**: `yfinance` explicitly works around a Yahoo bug where `interval=30m` can return `60m` bars on certain tickers by requesting `15m` and resampling (`history.py` line 266). Either inspect `meta.dataGranularity == "30m"` or aggregate `15m → 30m` locally (just like `LiveMarketService` already aggregates `60m → 4h`).
> 3. **Boundary clock-skew margin**: Request `59d` (not `60d`), `729d` (not `730d`), and `7d` chunks (not `8d`) for `1m` so server clock drift never triggers `HTTP 422`.

### 3.2 `period1` / `period2` Pagination Behavior

- **Units**: Unix epoch **seconds** (integers), unlike Binance's milliseconds.
- **Mutual exclusion**: Do **not** combine `range` with `period1`/`period2`.
- **Single-call coverage**: For `5m`, `15m`, `30m`, `60m`, and `1d`, Yahoo returns the **entire** retained window in a **single HTTP response** (up to ~14,500–17,000 bars). Only **`1m`** requires pagination: stitch at most **4 backward/forward chunks of 7 days** (`now - 29d` → `now`) and deduplicate on timestamp.

### 3.3 Throttling & `HTTP 429` Risks

Yahoo Finance enforces undocumented CDN/edge IP rate limits and anti-bot checks on `query1`/`query2.finance.yahoo.com`:
- **Headers**: Missing or non-browser `User-Agent` strings are rejected or aggressively throttled (MSNR Desk already sets a Safari-like `User-Agent`, which is good).
- **Polling amplification**: Currently `WorkspaceStore` polls every `10s` (`6 req/min`) for the full chart range. Adding multi-timeframe background refreshes or rapid instrument switching without caching will push bursts into `HTTP 429 Too Many Requests` (switching `query1` → `query2` shares the same IP reputation and does not reliably clear a `429`).
- **Required mitigations**:
  1. **Split initial backfill from live tail polling**: Load deep history **once** per `(symbol, timeframe)` into memory/disk cache. On the live poll timer, request only a tiny tail (`range=1d` for intraday or `period1 = lastBar - 3 * tf.seconds`) and merge into the cached series.
  2. **Timeframe-adaptive poll cadence**: Poll `M1`/`M5` every `10–15s`, `M15`/`M30` every `20–30s`, `H1`/`H4`/`D1` every `60s` (or derive HTF updates locally from a single `1m`/`5m` poll for the active Yahoo symbol!).
  3. **Respect market hours**: Pause polling when `instrument.marketStatus().isOpen == false` (weekends and `17:00–18:00 NY` gold rollover).
  4. **Pacing & 429 backoff**: Space sequential Yahoo backfill calls (`1m` chunks or multi-TF loads) by `350–500ms`, and on `HTTP 429` back off exponentially (`5s → 15s → 45s → 120s`) before retrying.

---

## 4. Practical Design Constraints for MSNR Desk

### 4.1 Safe Historical Depth & Bar Budgets (Multi-Timeframe Charts & Backtesting)

| Timeframe | Binance Target (Chart / Backtest) | Binance Requests & Weight | Yahoo Max Practical Depth (Chart / Backtest) | Yahoo Requests |
| :--- | :--- | :--- | :--- | :--- |
| **M1** | `2,000` chart (~1.4d) / `10,000–43,200` backtest (7–30d) | `2` req (`w=4`) / `10–44` req (`w=20–88`) | `~5,000–8,500` chart (5–7d) / `~25,000–34,000` backtest (29d) | `1` req / `4` stitched 7d reqs |
| **M5** | `2,000` chart (~7d) / `10,000–17,280` backtest (35–60d) | `2` req (`w=4`) / `10–18` req (`w=20–36`) | `~2,000–5,000` chart / `~11,500–14,400` backtest (59d max) | `1` req (`period1`/`period2`) |
| **M15** | `2,000` chart (~21d) / `6,000–10,000` backtest (62–104d) | `2` req (`w=4`) / `6–10` req (`w=12–20`) | `~2,000` chart / `~3,900–4,800` backtest (59d max) | `1` req (`period1`/`period2`) |
| **M30** | `1,500` chart (~31d) / `5,000` backtest (~104d) | `2` req (`w=4`) / `5` req (`w=10`) | `~1,500` chart / `~1,950–2,400` backtest (59d max; verify gran or resample `15m`) | `1` req (`period1`/`period2`) |
| **H1** | `1,500` chart (~62d) / `8,760–17,520` backtest (1–2y) | `2` req (`w=4`) / `9–18` req (`w=18–36`) | `~1,500` chart / `~12,500–14,500` backtest (729d max) | `1` req (`period1`/`period2`) |
| **H4** | `1,000` chart (~166d) / `4,380` backtest (2y) | `1` req (`w=2`) / `5` req (`w=10`) | Resample `60m` (729d) → `~3,100–3,600` H4 bars | `0` extra (reuse cached `60m`) |
| **D1** | `1,000` chart (~2.7y) / `2,000+` backtest | `1` req (`w=2`) / `2–3` req (`w=4–6`) | `1,000–5,000` bars (4–20y via `period1`/`period2`, **not** `range=max`) | `1` req |

### 4.2 Architectural Rules for MSNR Desk Implementation

1. **Multi-Timeframe (MTF) load budget**: Loading 4 timeframes simultaneously (e.g., `M5` + `M15` + `H1` + `H4` for MSNR HTF structure + LTF entry):
   - **Binance**: `2 + 2 + 2 + 1 = 7` requests (`weight = 14`, or `0.23%` of the 6,000/min IP limit). Safe even with concurrent fetches.
   - **Yahoo**: `3` requests (`5m`, `15m`, `60m` — derive `H4` locally from `60m`, and `M30` from `15m`), spaced `350ms` apart and cached per `(symbol, timeframe)` with TTL.
2. **Local disk cache**: Persist fetched historical candles (e.g., SQLite/JSON/binary cache keyed by `(provider, symbol, interval)`) so backtesting and timeframe switching only fetch incremental deltas (`startTime` / `period1` from last cached bar), eliminating repeat backfills.
3. **Header-driven Binance pacing**: Read `X-MBX-USED-WEIGHT-1M` on every Binance response; throttle pagination if `usedWeight >= 3000`, and honor `Retry-After` strictly on `429`/`418` without falling over to `api.binance.com`.
4. **Yahoo retention UI clarity**: When running backtests on Yahoo tickers (`GC=F`, `EURUSD=X`, `YM=F`, `NQ=F`), cap selectable backtest windows to `29d` (`M1`), `59d` (`M5`/`M15`/`M30`), and `729d` (`H1`/`H4`), or surface an explicit hint when a requested range exceeds Yahoo's intraday retention.

---

## Primary Sources

1. **Binance Spot REST API (`rest-api.md`)** — `GET /api/v3/klines`, pagination semantics, `HTTP 429`/`418`/`403`, `X-MBX-USED-WEIGHT-*`, `Retry-After`: https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md
2. **Binance Market Data Only FAQ (`faqs/market_data_only.md`)** — `data-api.binance.vision` & `data-stream.binance.vision` allowed endpoints/streams: https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md
3. **Binance WebSocket Streams (`web-socket-streams.md`)** — 24h lifetime, 20s ping / 1m pong timeout, `!serverShutdown`, 1,024 streams, 5 msg/s, 300 connections / 5 min / IP: https://github.com/binance/binance-spot-api-docs/blob/master/web-socket-streams.md
4. **Live Binance `exchangeInfo` & `klines` verification** — `https://data-api.binance.vision/api/v3/exchangeInfo?symbol=BTCUSDT` and `https://api.binance.com/api/v3/exchangeInfo?symbol=BTCUSDT` (confirmed `REQUEST_WEIGHT: 6000/1m`, `RAW_REQUESTS: 300000/5m`, `limit` clamping at `1000`, shared IP weight counter, and inclusive `endTime`).
5. **Live Yahoo Finance `v8/finance/chart` verification** — `https://query1.finance.yahoo.com/v8/finance/chart/{GC=F,EURUSD=X,YM=F,NQ=F}` (confirmed verbatim HTTP `422` retention errors for `1m`/`5m`/`15m`/`30m`/`60m`, `1m` 8d/request + 30d rolling cap, `range=max` `1d → 1mo` downgrade).
6. **`yfinance` History Scraper Source** — interval window constants & `30m → 15m` resampling workaround: https://github.com/ranaroussi/yfinance/blob/main/yfinance/scrapers/history.py
7. **Apple Foundation Documentation (`URLSessionWebSocketTask`)** — RFC 6455 transport framing & `sendPing(pongReceiveHandler:)`: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask
