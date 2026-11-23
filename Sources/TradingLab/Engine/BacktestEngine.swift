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
    let outcome: String // "TP", "SL", "EOD"
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

/// Causal bar-by-bar strategy evaluator running the user's 4-stage rules on live or sample candles.
enum BacktestEngine {
    static func run(
        candles: [Candle],
        indicators: ComputedIndicators,
        strategy: FourStageStrategyConfig,
        startingBalance: Double = 10_000.0
    ) -> BacktestReport {
        var report = BacktestReport(startingBalance: startingBalance, endingBalance: startingBalance)
        guard candles.count >= 60 else { return report }

        let adxThreshold = strategy.trendRules.first(where: { $0.kind == "adx" })?.value ?? 18.0
        let rsiCap = strategy.entryRules.first(where: { $0.kind == "rsi" })?.value ?? 72.0
        let rr = max(0.5, strategy.riskReward)
        let riskPct = max(0.1, min(5.0, strategy.riskPercent)) / 100.0
        let atrStopMult = max(0.8, strategy.nearATR * 2.4)

        var balance = startingBalance
        var peakBalance = startingBalance
        var maxDD = 0.0
        var equityCurve: [Double] = [startingBalance]
        var trades: [BacktestTrade] = []

        var i = 52
        while i < candles.count - 2 {
            let c = candles[i]
            guard let ema20 = indicators.ema20[i],
                  let ema50 = indicators.ema50[i],
                  let atr = indicators.atr[i], atr > 0,
                  let rsi = indicators.rsi[i],
                  let adx = indicators.adx[i] else {
                i += 1
                continue
            }

            let wt = indicators.waveTrend[i]
            let prev = candles[i - 1]

            // Stage 1: Trend filter (EMA alignment + ADX)
            let bullTrend = ema20 > ema50 && adx >= adxThreshold
            let bearTrend = ema20 < ema50 && adx >= adxThreshold

            // Stage 2 & 3: Retest near EMA20 or Order Block + confirmation candle
            let nearEMA20 = abs(c.low - ema20) <= atr * max(0.35, strategy.nearATR) || abs(c.high - ema20) <= atr * max(0.35, strategy.nearATR)
            let bullConfirm = c.isBullish && c.close > prev.high && rsi < rsiCap
            let bearConfirm = !c.isBullish && c.close < prev.low && rsi > (100.0 - rsiCap)
            let wtBull = (wt?.buySignal == true) || ((wt?.histogram ?? 0) > 0 && c.isBullish)
            let wtBear = (wt?.sellSignal == true) || ((wt?.histogram ?? 0) < 0 && !c.isBullish)

            var signalBuy: Bool? = nil
            var reason = ""
            if bullTrend && nearEMA20 && bullConfirm && wtBull {
                signalBuy = true
                reason = "EMA20 Retest + ADX \(Int(adx)) + Bull Confirm"
            } else if bearTrend && nearEMA20 && bearConfirm && wtBear {
                signalBuy = false
                reason = "EMA20 Retest + ADX \(Int(adx)) + Bear Confirm"
            }

            guard let isBuy = signalBuy else {
                i += 1
                continue
            }

            let entry = c.close
            let stopDist = atr * atrStopMult
            let sl = isBuy ? (entry - stopDist) : (entry + stopDist)
            let tp = isBuy ? (entry + stopDist * rr) : (entry - stopDist * rr)
            let riskMoney = balance * riskPct

            // Walk forward to resolve TP / SL causally
            var exitIdx = min(candles.count - 1, i + max(5, strategy.expiryBars))
            var exitPrice = candles[exitIdx].close
            var outcome = "EOD"
            var rResult = isBuy ? ((exitPrice - entry) / stopDist) : ((entry - exitPrice) / stopDist)

            for j in (i + 1)...exitIdx {
                let bar = candles[j]
                if isBuy {
                    if bar.low <= sl {
                        exitIdx = j
                        exitPrice = sl
                        outcome = "SL"
                        rResult = -1.0
                        break
                    }
                    if bar.high >= tp {
                        exitIdx = j
                        exitPrice = tp
                        outcome = "TP"
                        rResult = rr
                        break
                    }
                } else {
                    if bar.high >= sl {
                        exitIdx = j
                        exitPrice = sl
                        outcome = "SL"
                        rResult = -1.0
                        break
                    }
                    if bar.low <= tp {
                        exitIdx = j
                        exitPrice = tp
                        outcome = "TP"
                        rResult = rr
                        break
                    }
                }
            }

            let pnl = riskMoney * rResult
            balance += pnl
            peakBalance = max(peakBalance, balance)
            let dd = peakBalance > 0 ? ((peakBalance - balance) / peakBalance) * 100.0 : 0
            maxDD = max(maxDD, dd)
            equityCurve.append(balance)

            trades.append(BacktestTrade(
                id: trades.count,
                entryIndex: i,
                exitIndex: exitIdx,
                entryTime: c.timestamp,
                exitTime: candles[exitIdx].timestamp,
                isBuy: isBuy,
                entryPrice: entry,
                stopLoss: sl,
                takeProfit: tp,
                exitPrice: exitPrice,
                rMultiple: rResult,
                pnlUSD: pnl,
                outcome: outcome,
                reason: reason
            ))

            // Advance past exit bar to prevent overlapping trades
            i = exitIdx + 1
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
}
