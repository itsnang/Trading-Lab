import Foundation

struct BacktestTrade: Identifiable, Hashable {
    let id: Int
    let entryIndex: Int
    let exitIndex: Int
    let entryTime: Date
    let exitTime: Date
    let isBuy: Bool
    let entryPrice: Double
    let stopLoss: Double
    let takeProfit: Double
    let exitPrice: Double
    let rMultiple: Double
    let pnlUSD: Double
    let outcome: String // "TP", "SL", "BE+TP1", "EOD"
    let reason: String
}

struct BacktestReport {
    var trades: [BacktestTrade] = []
    var equityCurve: [Double] = [10_000]
    var startingBalance: Double = 10_000
    var endingBalance: Double = 10_000
    var winRate: Double = 0
    var profitFactor: Double = 0
    var totalR: Double = 0
    var maxDrawdownPct: Double = 0
    var averageR: Double = 0
}

private struct CausalOrderBlock {
    let obIndex: Int
    let confirmedIndex: Int
    let top: Double
    let bottom: Double
    let isBullish: Bool
    let pressurePercent: Double
}

/// Unified causal 4-Stage Strategy Engine shared by Strategy Lab (Backtest + Bot Studio) and Chart Setups.
/// Strictly causal: decisions at bar `i` inspect only bars `0...i` (zero lookahead).
enum BacktestEngine {
    static func run(
        candles: [Candle],
        indicators: ComputedIndicators,
        strategy: FourStageStrategyConfig,
        startingBalance: Double = 10_000.0
    ) -> BacktestReport {
        var report = BacktestReport(startingBalance: startingBalance, endingBalance: startingBalance)
        guard candles.count >= 45 else { return report }

        let rr = max(0.5, strategy.riskReward)
        let riskPct = max(0.1, min(5.0, strategy.riskPercent)) / 100.0
        let nearATRMult = max(0.15, strategy.nearATR)
        let atrStopMult = max(0.8, nearATRMult * 2.2)
        let beRR = max(0.5, strategy.breakevenRR)
        let partialOn = strategy.partialTakeProfit

        // Incremental causal structure & order-block discovery (only confirms pivots once `lookback` right-side bars have closed!)
        let lb = 4
        var lastSwingHigh: (idx: Int, price: Double)? = nil
        var lastSwingLow: (idx: Int, price: Double)? = nil
        var highBroken = false
        var lowBroken = false
        var activeBlocks: [CausalOrderBlock] = []

        var balance = startingBalance
        var peakBalance = startingBalance
        var maxDD = 0.0
        var equityCurve: [Double] = [startingBalance]
        var trades: [BacktestTrade] = []
        var nextEligibleEntryIdx = 25

        for i in (lb * 2 + 1)..<(candles.count - 1) {
            // 1. Confirm pivot at `pivIdx = i - lb` using only bars `(pivIdx - lb)...i` (100% causal!)
            let pivIdx = i - lb
            let ph = candles[pivIdx].high
            let pl = candles[pivIdx].low
            var isHigh = true
            var isLow = true
            for j in (pivIdx - lb)...i where j != pivIdx {
                if j < pivIdx {
                    if candles[j].high > ph { isHigh = false }
                    if candles[j].low < pl { isLow = false }
                } else {
                    if candles[j].high >= ph { isHigh = false }
                    if candles[j].low <= pl { isLow = false }
                }
            }
            if isHigh { lastSwingHigh = (pivIdx, ph); highBroken = false }
            if isLow { lastSwingLow = (pivIdx, pl); lowBroken = false }

            let cur = candles[i]

            // 2. Remove any blocks mitigated by prior bars up to `i - 1`
            if i > 0 {
                let prevBar = candles[i - 1]
                activeBlocks.removeAll { blk in
                    guard blk.confirmedIndex < i - 1 else { return false }
                    return blk.isBullish ? (prevBar.close < blk.bottom) : (prevBar.close > blk.top)
                }
            }

            // 3. Detect causal structure break at bar `i` and register newly confirmed Order Block
            if let sh = lastSwingHigh, !highBroken, cur.close > sh.price, i > sh.idx + 1 {
                highBroken = true
                if let obIdx = ((sh.idx)..<i).reversed().first(where: { !candles[$0].isBullish }) {
                    let obC = candles[obIdx]
                    let pressure = causalBlockPressure(candles: candles, from: obIdx, to: i, isBullish: true)
                    activeBlocks.append(CausalOrderBlock(
                        obIndex: obIdx,
                        confirmedIndex: i,
                        top: obC.high,
                        bottom: obC.low,
                        isBullish: true,
                        pressurePercent: pressure
                    ))
                }
            }
            if let sl = lastSwingLow, !lowBroken, cur.close < sl.price, i > sl.idx + 1 {
                lowBroken = true
                if let obIdx = ((sl.idx)..<i).reversed().first(where: { candles[$0].isBullish }) {
                    let obC = candles[obIdx]
                    let pressure = causalBlockPressure(candles: candles, from: obIdx, to: i, isBullish: false)
                    activeBlocks.append(CausalOrderBlock(
                        obIndex: obIdx,
                        confirmedIndex: i,
                        top: obC.high,
                        bottom: obC.low,
                        isBullish: false,
                        pressurePercent: pressure
                    ))
                }
            }

            // Do not open overlapping trades
            guard i >= nextEligibleEntryIdx else { continue }
            guard let ema20 = indicators.ema20[i],
                  let ema50 = indicators.ema50[i],
                  let atr = indicators.atr[i], atr > 0,
                  let rsi = indicators.rsi[i],
                  let adx = indicators.adx[i] else { continue }

            // Compute causal bar metrics at `i` using only `0...i`
            let winStart = max(0, i - 20)
            let window = candles[winStart..<i]
            let avgRange = max(window.reduce(0.0) { $0 + $1.range } / Double(max(1, window.count)), 1e-6)
            let closePos = (cur.close - cur.low) / max(cur.range, 1e-6)
            let estDelta = abs((closePos * 2.0 - 1.0) * max(cur.volume, 1.0)) * 12.0
            let isAxBar = cur.range >= avgRange * 1.15 && abs(cur.close - cur.open) >= cur.range * 0.42
            let atrRatio = cur.range / atr

            // Evaluate 4-stage rules for BUY (true) and SELL (false)
            var matchedSide: (isBuy: Bool, pressure: Double)? = nil
            for candidateBuy in [true, false] {
                // Direction & momentum alignment
                if candidateBuy && !cur.isBullish { continue }
                if !candidateBuy && cur.isBullish { continue }

                // Stage 1: Trend Rules
                let trendPass = strategy.trendRules.allSatisfy { cond in
                    evaluateCondition(
                        cond,
                        isBuy: candidateBuy,
                        adx: adx,
                        rsi: rsi,
                        ema20: ema20,
                        ema50: ema50,
                        blockPressure: 0,
                        blockTouches: 0,
                        isAx: isAxBar,
                        delta: estDelta,
                        atrRatio: atrRatio
                    )
                }
                guard trendPass else { continue }

                // Find best active causal Order Block (or trend pullback zone) on this side
                let candidateBlocks = activeBlocks.filter { $0.isBullish == candidateBuy && $0.confirmedIndex <= i }
                let bestPressure: Double
                let touchCount: Int
                if let bestOB = candidateBlocks.max(by: { $0.pressurePercent < $1.pressurePercent }) {
                    bestPressure = bestOB.pressurePercent
                    let tol = atr * nearATRMult
                    let lbStart = max(bestOB.confirmedIndex, i - max(1, strategy.confirmationBars))
                    let touched = (lbStart...i).contains { k in
                        let b = candles[k]
                        return b.low <= bestOB.top + tol && b.high >= bestOB.bottom - tol
                    }
                    touchCount = touched ? 1 : 0
                } else {
                    // Fallback to EMA20 structure pullback if no OB formed yet
                    bestPressure = causalBlockPressure(candles: candles, from: max(0, i - 6), to: i, isBullish: candidateBuy)
                    let nearEMA = abs(cur.low - ema20) <= atr * nearATRMult || abs(cur.high - ema20) <= atr * nearATRMult
                    let trendAligned = candidateBuy ? (ema20 >= ema50 * 0.999) : (ema20 <= ema50 * 1.001)
                    touchCount = (nearEMA && trendAligned) ? 1 : 0
                }

                // Stage 2: Setup Rules (e.g., blockPressure > 55)
                let setupPass = strategy.setupRules.allSatisfy { cond in
                    evaluateCondition(
                        cond,
                        isBuy: candidateBuy,
                        adx: adx,
                        rsi: rsi,
                        ema20: ema20,
                        ema50: ema50,
                        blockPressure: bestPressure,
                        blockTouches: Double(touchCount),
                        isAx: isAxBar,
                        delta: estDelta,
                        atrRatio: atrRatio
                    )
                }
                guard setupPass else { continue }

                // Stage 3: Retest Rules (e.g., blockTouch >= 1)
                let retestPass = strategy.retestRules.allSatisfy { cond in
                    evaluateCondition(
                        cond,
                        isBuy: candidateBuy,
                        adx: adx,
                        rsi: rsi,
                        ema20: ema20,
                        ema50: ema50,
                        blockPressure: bestPressure,
                        blockTouches: Double(touchCount),
                        isAx: isAxBar,
                        delta: estDelta,
                        atrRatio: atrRatio
                    )
                }
                guard retestPass else { continue }

                // Stage 4: Entry Confirmation Rules (e.g., delta / ax / rsi)
                let entryPass = strategy.entryRules.allSatisfy { cond in
                    evaluateCondition(
                        cond,
                        isBuy: candidateBuy,
                        adx: adx,
                        rsi: rsi,
                        ema20: ema20,
                        ema50: ema50,
                        blockPressure: bestPressure,
                        blockTouches: Double(touchCount),
                        isAx: isAxBar,
                        delta: estDelta,
                        atrRatio: atrRatio
                    )
                }
                guard entryPass else { continue }

                matchedSide = (candidateBuy, bestPressure)
                break
            }

            guard let match = matchedSide else { continue }

            let isBuy = match.isBuy
            let entry = cur.close
            let stopDist = atr * atrStopMult
            let initialSL = isBuy ? (entry - stopDist) : (entry + stopDist)
            let tp = isBuy ? (entry + stopDist * rr) : (entry - stopDist * rr)
            let tp1Price = isBuy ? (entry + stopDist * beRR) : (entry - stopDist * beRR)
            let riskMoney = balance * riskPct

            var activeSL = initialSL
            var partialBanked = false
            var exitIdx = min(candles.count - 1, i + max(5, strategy.expiryBars))
            var exitPrice = candles[exitIdx].close
            var outcome = "EOD"
            var rResult = isBuy ? ((exitPrice - entry) / stopDist) : ((entry - exitPrice) / stopDist)

            for j in (i + 1)...exitIdx {
                let bar = candles[j]
                if isBuy {
                    // Conservative SL-first intra-bar check
                    if bar.low <= activeSL {
                        exitIdx = j
                        exitPrice = activeSL
                        if partialBanked {
                            outcome = "BE+TP1"
                            rResult = 0.5 * beRR
                        } else {
                            outcome = "SL"
                            rResult = -1.0
                        }
                        break
                    }
                    if bar.high >= tp {
                        exitIdx = j
                        exitPrice = tp
                        outcome = "TP"
                        rResult = partialBanked ? (0.5 * beRR + 0.5 * rr) : rr
                        break
                    }
                    if partialOn && !partialBanked && bar.high >= tp1Price && rr > beRR {
                        partialBanked = true
                        activeSL = entry // Move remaining 50% stop to breakeven
                    }
                } else {
                    if bar.high >= activeSL {
                        exitIdx = j
                        exitPrice = activeSL
                        if partialBanked {
                            outcome = "BE+TP1"
                            rResult = 0.5 * beRR
                        } else {
                            outcome = "SL"
                            rResult = -1.0
                        }
                        break
                    }
                    if bar.low <= tp {
                        exitIdx = j
                        exitPrice = tp
                        outcome = "TP"
                        rResult = partialBanked ? (0.5 * beRR + 0.5 * rr) : rr
                        break
                    }
                    if partialOn && !partialBanked && bar.low <= tp1Price && rr > beRR {
                        partialBanked = true
                        activeSL = entry
                    }
                }
            }

            if outcome == "EOD" && partialBanked {
                let remR = isBuy ? ((exitPrice - entry) / stopDist) : ((entry - exitPrice) / stopDist)
                rResult = 0.5 * beRR + 0.5 * remR
            }

            let pnl = riskMoney * rResult
            balance += pnl
            peakBalance = max(peakBalance, balance)
            let dd = peakBalance > 0 ? ((peakBalance - balance) / peakBalance) * 100.0 : 0
            maxDD = max(maxDD, dd)
            equityCurve.append(balance)

            let reason = String(format: "4-Stage OB %.0f%% + Δ%.0f + ADX %.0f", match.pressure, estDelta, adx)
            trades.append(BacktestTrade(
                id: trades.count,
                entryIndex: i,
                exitIndex: exitIdx,
                entryTime: cur.timestamp,
                exitTime: candles[exitIdx].timestamp,
                isBuy: isBuy,
                entryPrice: entry,
                stopLoss: initialSL,
                takeProfit: tp,
                exitPrice: exitPrice,
                rMultiple: rResult,
                pnlUSD: pnl,
                outcome: outcome,
                reason: reason
            ))

            nextEligibleEntryIdx = exitIdx + 1
        }

        let wins = trades.filter { $0.pnlUSD > 0 }
        let losses = trades.filter { $0.pnlUSD < 0 }
        let grossWin = wins.reduce(0.0) { $0 + $1.pnlUSD }
        let grossLoss = abs(losses.reduce(0.0) { $0 + $1.pnlUSD })

        report.trades = trades
        report.equityCurve = equityCurve
        report.endingBalance = balance
        report.winRate = trades.isEmpty ? 0 : (Double(wins.count) / Double(trades.count)) * 100.0
        report.profitFactor = grossLoss > 0 ? (grossWin / grossLoss) : (grossWin > 0 ? 9.99 : 0)
        report.totalR = trades.reduce(0.0) { $0 + $1.rMultiple }
        report.averageR = trades.isEmpty ? 0 : (report.totalR / Double(trades.count))
        report.maxDrawdownPct = maxDD
        return report
    }

    private static func causalBlockPressure(candles: [Candle], from startIdx: Int, to endIdx: Int, isBullish: Bool) -> Double {
        let lo = max(0, min(startIdx, endIdx))
        let hi = min(candles.count - 1, max(startIdx, endIdx))
        var bullVol = 0.0
        var bearVol = 0.0
        for j in lo...hi {
            let c = candles[j]
            let range = max(c.range, 1e-6)
            let closePos = max(0.05, min(0.95, (c.close - c.low) / range))
            bullVol += c.volume * closePos
            bearVol += c.volume * (1.0 - closePos)
        }
        let total = max(bullVol + bearVol, 1e-6)
        return ((isBullish ? bullVol : bearVol) / total) * 100.0
    }

    private static func evaluateCondition(
        _ cond: RuleCondition,
        isBuy: Bool,
        adx: Double,
        rsi: Double,
        ema20: Double,
        ema50: Double,
        blockPressure: Double,
        blockTouches: Double,
        isAx: Bool,
        delta: Double,
        atrRatio: Double
    ) -> Bool {
        let lhs: Double
        switch cond.kind {
        case "adx":
            lhs = adx
        case "rsi":
            // Symmetric RSI cap for Buy (rsi < 70) vs Sell (100 - rsi < 70 => rsi > 30)
            lhs = isBuy ? rsi : (100.0 - rsi)
        case "blockPressure":
            lhs = blockPressure
        case "blockTouch":
            lhs = blockTouches
        case "ax":
            lhs = isAx ? 1.0 : 0.0
        case "delta", "signedDelta":
            lhs = delta
        case "atrRatio":
            lhs = atrRatio
        default:
            lhs = 1.0
        }

        switch cond.compare {
        case "gt": return lhs > cond.value
        case "gte": return lhs >= cond.value
        case "lt": return lhs < cond.value
        case "lte": return lhs <= cond.value
        default: return lhs >= cond.value
        }
    }
}
