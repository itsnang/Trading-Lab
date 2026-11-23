# Trading-Lab

**MSNR Desk (Trading Lab)** — a native macOS SwiftUI charting, indicator, backtesting, and paper-trading desktop workspace.

## Features
- **Live & Sample Market Feeds**: Zero-API-key live WebSocket + Order Flow tape (`PAXG/USDT`, `BTC/USD`, `ETH/USD` via Binance) and REST polling (`XAU/USD`, `EUR/USD`, `US30`, `NAS100` via Yahoo Finance) alongside deterministic Sample mode.
- **TradingView-Style Chart Ergonomics**: Cursor-anchored scroll zoom, right price-axis vertical scaling & `Auto` fit, bottom time-axis zoom, 2D pan, Magnet OHLC snapping, selectable & resizable drawings with undo/duplicate/delete, live bar countdown, Bar Replay, and draggable oscillator/trade splitters.
- **6 Local Indicator Suites**:
  1. **Market Structure 2.0** — Dual-tier Internal/Macro `BOS`/`CHoCH`/`CHoCH+`, Order Blocks with directional pressure %, RSI Regular Divergences, EMAs, and Visible-Range Volume Profile + POC.
  2. **Order Flow & Delta** — `BuAx+`/`BuAx-`/`BeAx+`/`BeAx-` Accelerator markers, Wickless `★` stars, Protected Swing Levels, Fair Value Gaps, and High-Volume Zones.
  3. **Reversal & ATR Targets** — Dynamic Volatility Envelope (`13 × 2.718`), Bollinger/RSI Reversals, `ATR` Stop + `TP1`/`TP2`/`TP3`, and `PDH`/`PDL`.
  4. **Session Toolkits** — 70% Value Area Profile, Camarilla & Fibonacci `P2–P5` Pivots, 5-day ADR, and Killzone readiness.
  5. **Sideway Detector** — Scalp Zones (impulse → quiet → OB pressure), ADX Cycle (`10/50/30`), ADR Gate, and UTC+7 Working Hours.
  6. **Momentum Oscillator** — WaveTrend (`10, 21`), Smart Reversal dots, Regular Divergences, ZVWAP (`20`), and Smoothed Heikin-Ashi Trend Ribbon.
- **Local Persistence**: Automatically saves all settings, indicators, drawings, alerts, journal entries, and paper account state to `~/Library/Application Support/TradingLab/`.

## Build & Run (macOS 14+)

```bash
./build_app.sh
open build/TradingLab.app
```
