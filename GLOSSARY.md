# MSNR Desk (Trading-Lab)

A personal macOS discretionary day-trading and strategy-validation cockpit for analyzing live or simulated markets, testing rules causally, practicing risk-managed execution, and journaling performance.

## Language

**Feed Mode**:
The source of market candles and trade ticks powering the terminal: either `Live` (real-time external market data) or `Simulated` (deterministic synthetic candles).
_Avoid_: Sample mode (when referring to paper execution), demo feed

**Paper Desk**:
The simulated order execution and position management system—including fills, stops, targets, and equity tracking—that operates identically on either `Live` or `Simulated` feeds with zero real-money risk.
_Avoid_: Sample account, demo account

**Strategy Engine**:
The single causal rule evaluator shared by Chart Setups, the Backtester, and Signal Alerts so every surface measures and triggers on the exact same conditions.
_Avoid_: Bot Studio rules, backtest formula, setup script

**Study Suite**:
A bundled group of related local chart overlays or oscillators (such as Market Structure 2.0 or Order Flow & Delta) that can be added, hidden, configured, or alerted as one unit.
_Avoid_: Company indicator, plugin
