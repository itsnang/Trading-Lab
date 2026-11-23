import Foundation

enum IndicatorEngine {

    static func computeAll(candles: [Candle], config: IndicatorConfig) -> ComputedIndicators {
        var out = ComputedIndicators()
        guard candles.count >= 5 else { return out }

        let closes = candles.map(\.close)
        out.ema20 = ema(closes, period: 20)
        out.ema50 = ema(closes, period: 50)
        out.ema200 = ema(closes, period: 200)

        // Bollinger Bands (20, 2.0)
        let bb = bollingerBands(closes, period: max(2, config.revBBLength), deviation: config.revBBMultiplier)
        out.bbUpper = bb.upper
        out.bbMiddle = bb.middle
        out.bbLower = bb.lower

        // Volatility Envelope (13 x 2.718)
        let volBand = computeVolatilityEnvelope(
            candles: candles,
            length: max(2, config.revVolatilityLength),
            multiplier: max(0.3, config.revVolatilityMultiplier)
        )
        out.volatilityUpper = volBand.upper
        out.volatilityLower = volBand.lower
        out.volatilityTrend = volBand.trend

        out.rsi = rsi(closes, period: max(2, config.rsiLength))
        out.atr = atr(candles, period: max(2, config.atrLength))
        out.adx = adx(candles, period: max(3, config.sidewayADXLength))

        // 6. Momentum Oscillator: WaveTrend + Divergences + HA Bias + ZVWAP
        out.waveTrend = waveTrend(
            candles,
            channelLength: max(2, config.wtChannelLength),
            averageLength: max(2, config.wtAverageLength),
            overbought: config.wtOverbought,
            oversold: config.wtOversold,
            smartOnly: config.oscSmartOnly
        )
        out.oscDivergences = detectOscillatorDivergences(candles: candles, waveTrend: out.waveTrend)
        out.zvwap = computeZVWAP(candles: candles, length: max(5, config.oscZVWAPLength))
        out.haBiasBullish = computeHeikinAshiBias(
            candles: candles,
            preLength: max(2, config.oscHALength),
            smoothLength: max(2, config.oscHASmoothing)
        )

        // 1. Market Structure 2.0: Internal(5) + Macro(20) BOS/CHoCH/CHoCH+ & OBs with Pressure % + RSI Divergences
        let structure = detectDualTierStructureAndBlocks(
            candles: candles,
            internalLookback: max(2, min(12, config.conceptSwingLookback)),
            macroLookback: max(8, min(40, config.conceptMacroSwingLookback)),
            maxActivePerSide: max(1, min(8, config.conceptOrderCount))
        )
        out.structureBreaks = structure.breaks
        out.orderBlocks = structure.blocks
        out.rsiDivergences = detectRSIDivergences(candles: candles, rsi: out.rsi, pivot: max(3, config.conceptSwingLookback))

        // 2. Order Flow & Delta: BuAx+/BuAx-/BeAx+/BeAx-, Protected Levels, FVGs, Volume Zones
        out.fvgs = detectFVGs(candles: candles)
        out.accelerators = detectAccelerators(
            candles: candles,
            rangeFactor: config.orderFlowRangeFactor,
            deltaFactor: config.orderFlowDeltaFactor,
            plusOnly: config.orderFlowPlusOnly
        )
        out.protectedLevels = detectProtectedLevels(candles: candles, lookback: max(4, config.conceptSwingLookback + 2))
        out.volumeZones = detectVolumeZones(
            candles: candles,
            threshold: max(1.3, config.orderFlowVolumeThreshold),
            avgLen: 20,
            maxZones: 5
        )

        // 3. Reversal & ATR Targets: BB(width >= 0.0015) + RSI(25/72) + ATR(2.0x) SL + TP1/2/3
        out.reversalSignals = detectReversalTargets(
            candles: candles,
            bbUpper: out.bbUpper,
            bbMiddle: out.bbMiddle,
            bbLower: out.bbLower,
            rsi: out.rsi,
            atr: out.atr,
            config: config
        )

        // 4. Session Toolkits: Camarilla / Fibonacci P2-P5
        out.pivots = computePivots(candles: candles, kind: config.toolkitPivotKind)

        // 5. Sideway Detector: Scalp Zones + ADX Cycle + ADR Gate + UTC+7 Working Hours
        out.scalpZones = detectScalpZones(
            candles: candles,
            atr: out.atr,
            orderBlocks: out.orderBlocks,
            config: config
        )

        out.lastATR = out.atr.last.flatMap { $0 } ?? 0
        out.lastADX = out.adx.last.flatMap { $0 } ?? 0
        out.lastRSI = out.rsi.last.flatMap { $0 } ?? 50
        out.lastZVWAP = out.zvwap.last.flatMap { $0 } ?? 0

        // ADX Cycle state: detect if ADX peaked recently and is now compressing
        let recentMaxADX = out.adx.suffix(18).compactMap { $0 }.max() ?? out.lastADX
        let regime: String
        if out.lastADX >= config.sidewayADXPeak {
            regime = "Strong Trend"
        } else if out.lastADX <= config.sidewayADXFlat {
            regime = "Sideway / Flat"
        } else if recentMaxADX >= config.sidewayADXPeak && out.lastADX < recentMaxADX - 4.0 {
            regime = "Compressing"
        } else {
            regime = "Balanced"
        }
        out.marketRegime = regime

        let lastEMA20 = out.ema20.last.flatMap { $0 }
        let lastEMA50 = out.ema50.last.flatMap { $0 }
        let htfBias: String
        if let e20 = lastEMA20, let e50 = lastEMA50 {
            if e20 > e50 * 1.0002 { htfBias = "Bullish" }
            else if e20 < e50 * 0.9998 { htfBias = "Bearish" }
            else { htfBias = "Neutral" }
        } else {
            htfBias = "Neutral"
        }

        // Compute ADR % used from last 24-bar rolling session vs 5-session average
        let sessionBars = min(24, candles.count)
        let currentSlice = candles.suffix(sessionBars)
        let curRange = (currentSlice.map(\.high).max() ?? 0) - (currentSlice.map(\.low).min() ?? 0)
        var histRanges: [Double] = []
        var offset = sessionBars
        while offset + sessionBars <= candles.count && histRanges.count < 5 {
            let start = candles.count - offset - sessionBars
            let end = candles.count - offset
            let s = candles[start..<end]
            let r = (s.map(\.high).max() ?? 0) - (s.map(\.low).min() ?? 0)
            if r > 0 { histRanges.append(r) }
            offset += sessionBars
        }
        let avgADR = histRanges.isEmpty ? max(curRange, 1e-6) : (histRanges.reduce(0, +) / Double(histRanges.count))
        let adrPct = (curRange / max(avgADR, 1e-6)) * 100.0

        let prevHigh: Double?
        let prevLow: Double?
        if candles.count >= sessionBars * 2 {
            let prevSlice = candles[(candles.count - sessionBars * 2)..<(candles.count - sessionBars)]
            prevHigh = prevSlice.map(\.high).max()
            prevLow = prevSlice.map(\.low).min()
        } else {
            prevHigh = nil
            prevLow = nil
        }

        var utc7Cal = Calendar(identifier: .gregorian)
        utc7Cal.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current
        let now = Date()
        let localHour = utc7Cal.component(.hour, from: now)
        let localMin = utc7Cal.component(.minute, from: now)
        let curMins = localHour * 60 + localMin
        let startMins = config.sidewayWorkStartHour * 60
        let endMins = config.sidewayWorkEndHour * 60
        let inHours = curMins >= startMins && curMins < endMins
        let cutoffWarning = inHours && curMins >= (endMins - config.sidewayCutoffMins)

        out.sideway = SidewayStatus(
            adxValue: out.lastADX,
            regimeLabel: regime,
            htfBias: htfBias,
            adrUsedPercent: adrPct,
            adrGateOpen: adrPct >= config.sidewayADRGatePct,
            adrDanger: adrPct >= config.sidewayADRDangerPct,
            inWorkingHoursUTC7: inHours,
            cutoffWarning: cutoffWarning,
            activeScalpZones: out.scalpZones.count,
            prevSessionHigh: prevHigh,
            prevSessionLow: prevLow
        )

        return out
    }

    // MARK: - Core Math

    static func ema(_ values: [Double], period: Int) -> [Double?] {
        let n = values.count
        guard n >= period, period > 0 else { return Array(repeating: nil, count: n) }
        var result: [Double?] = Array(repeating: nil, count: n)
        let k = 2.0 / Double(period + 1)
        var sum = 0.0
        for i in 0..<period { sum += values[i] }
        var prev = sum / Double(period)
        result[period - 1] = prev
        for i in period..<n {
            prev = values[i] * k + prev * (1.0 - k)
            result[i] = prev
        }
        return result
    }

    static func sma(_ values: [Double], period: Int) -> [Double?] {
        let n = values.count
        guard n >= period, period > 0 else { return Array(repeating: nil, count: n) }
        var result: [Double?] = Array(repeating: nil, count: n)
        var sum = 0.0
        for i in 0..<n {
            sum += values[i]
            if i >= period { sum -= values[i - period] }
            if i >= period - 1 { result[i] = sum / Double(period) }
        }
        return result
    }

    static func bollingerBands(_ values: [Double], period: Int, deviation: Double) -> (upper: [Double?], middle: [Double?], lower: [Double?]) {
        let n = values.count
        let mid = sma(values, period: period)
        var upper: [Double?] = Array(repeating: nil, count: n)
        var lower: [Double?] = Array(repeating: nil, count: n)
        guard n >= period else { return (upper, mid, lower) }

        for i in (period - 1)..<n {
            guard let m = mid[i] else { continue }
            var variance = 0.0
            for j in (i - period + 1)...i {
                let d = values[j] - m
                variance += d * d
            }
            let sd = sqrt(variance / Double(period))
            upper[i] = m + sd * deviation
            lower[i] = m - sd * deviation
        }
        return (upper, mid, lower)
    }

    /// Clean-room dynamic Volatility Envelope (SuperTrend-style ATR band using length=13, mult=2.718).
    static func computeVolatilityEnvelope(
        candles: [Candle],
        length: Int,
        multiplier: Double
    ) -> (upper: [Double?], lower: [Double?], trend: [Int]) {
        let n = candles.count
        var upper: [Double?] = Array(repeating: nil, count: n)
        var lower: [Double?] = Array(repeating: nil, count: n)
        var trend: [Int] = Array(repeating: 1, count: n)
        let atrSeries = atr(candles, period: length)
        guard n > length else { return (upper, lower, trend) }

        var prevUpper = 0.0
        var prevLower = 0.0
        var curTrend = 1

        for i in length..<n {
            guard let av = atrSeries[i] else { continue }
            let hl2 = (candles[i].high + candles[i].low) * 0.5
            let rawUpper = hl2 + multiplier * av
            let rawLower = hl2 - multiplier * av

            if i == length {
                prevUpper = rawUpper
                prevLower = rawLower
            } else {
                let prevClose = candles[i - 1].close
                prevUpper = (rawUpper < prevUpper || prevClose > prevUpper) ? rawUpper : prevUpper
                prevLower = (rawLower > prevLower || prevClose < prevLower) ? rawLower : prevLower
            }

            if curTrend == 1 && candles[i].close < prevLower {
                curTrend = -1
            } else if curTrend == -1 && candles[i].close > prevUpper {
                curTrend = 1
            }

            trend[i] = curTrend
            upper[i] = prevUpper
            lower[i] = prevLower
        }
        return (upper, lower, trend)
    }

    static func rsi(_ closes: [Double], period: Int) -> [Double?] {
        let n = closes.count
        var result: [Double?] = Array(repeating: nil, count: n)
        guard n > period else { return result }

        var avgGain = 0.0
        var avgLoss = 0.0
        for i in 1...period {
            let change = closes[i] - closes[i - 1]
            if change >= 0 { avgGain += change } else { avgLoss += -change }
        }
        avgGain /= Double(period)
        avgLoss /= Double(period)
        result[period] = avgLoss == 0 ? 100.0 : 100.0 - (100.0 / (1.0 + avgGain / avgLoss))

        for i in (period + 1)..<n {
            let change = closes[i] - closes[i - 1]
            let gain = max(change, 0)
            let loss = max(-change, 0)
            avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
            result[i] = avgLoss == 0 ? 100.0 : 100.0 - (100.0 / (1.0 + avgGain / avgLoss))
        }
        return result
    }

    static func atr(_ candles: [Candle], period: Int) -> [Double?] {
        let n = candles.count
        var result: [Double?] = Array(repeating: nil, count: n)
        guard n > period else { return result }

        var trs = [Double](repeating: 0, count: n)
        trs[0] = candles[0].high - candles[0].low
        for i in 1..<n {
            let h = candles[i].high
            let l = candles[i].low
            let pc = candles[i - 1].close
            trs[i] = max(h - l, max(abs(h - pc), abs(l - pc)))
        }

        var sum = 0.0
        for i in 0..<period { sum += trs[i] }
        var prev = sum / Double(period)
        result[period - 1] = prev
        for i in period..<n {
            prev = (prev * Double(period - 1) + trs[i]) / Double(period)
            result[i] = prev
        }
        return result
    }

    static func adx(_ candles: [Candle], period: Int) -> [Double?] {
        let n = candles.count
        var result: [Double?] = Array(repeating: nil, count: n)
        guard n > period * 2 else { return result }

        var tr = [Double](repeating: 0, count: n)
        var plusDM = [Double](repeating: 0, count: n)
        var minusDM = [Double](repeating: 0, count: n)

        for i in 1..<n {
            let upMove = candles[i].high - candles[i - 1].high
            let downMove = candles[i - 1].low - candles[i].low
            plusDM[i] = (upMove > downMove && upMove > 0) ? upMove : 0
            minusDM[i] = (downMove > upMove && downMove > 0) ? downMove : 0
            tr[i] = max(
                candles[i].high - candles[i].low,
                max(abs(candles[i].high - candles[i - 1].close), abs(candles[i].low - candles[i - 1].close))
            )
        }

        var smoothTR = 0.0, smoothPlus = 0.0, smoothMinus = 0.0
        for i in 1...period {
            smoothTR += tr[i]
            smoothPlus += plusDM[i]
            smoothMinus += minusDM[i]
        }

        var dx = [Double](repeating: 0, count: n)
        for i in period..<n {
            if i > period {
                smoothTR = smoothTR - (smoothTR / Double(period)) + tr[i]
                smoothPlus = smoothPlus - (smoothPlus / Double(period)) + plusDM[i]
                smoothMinus = smoothMinus - (smoothMinus / Double(period)) + minusDM[i]
            }
            let pdi = smoothTR > 0 ? (100.0 * smoothPlus / smoothTR) : 0
            let mdi = smoothTR > 0 ? (100.0 * smoothMinus / smoothTR) : 0
            let denom = pdi + mdi
            dx[i] = denom > 0 ? (100.0 * abs(pdi - mdi) / denom) : 0
        }

        var adxSum = 0.0
        let start = period * 2 - 1
        for i in period...start { adxSum += dx[i] }
        var prevADX = adxSum / Double(period)
        result[start] = prevADX
        for i in (start + 1)..<n {
            prevADX = (prevADX * Double(period - 1) + dx[i]) / Double(period)
            result[i] = prevADX
        }
        return result
    }

    // MARK: - 6. Momentum Oscillator (WaveTrend + Divergences + ZVWAP + HA Bias)

    static func waveTrend(
        _ candles: [Candle],
        channelLength: Int,
        averageLength: Int,
        overbought: Double,
        oversold: Double,
        smartOnly: Bool
    ) -> [WaveTrendPoint?] {
        let n = candles.count
        var result: [WaveTrendPoint?] = Array(repeating: nil, count: n)
        guard n > channelLength + averageLength + 4 else { return result }

        let ap = candles.map(\.hlc3)
        let esa = ema(ap, period: channelLength)

        var absDiff = [Double](repeating: 0, count: n)
        for i in 0..<n { absDiff[i] = abs(ap[i] - (esa[i] ?? ap[i])) }
        let d = ema(absDiff, period: channelLength)

        var ci = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if let e = esa[i], let dv = d[i], dv > 1e-9 {
                ci[i] = (ap[i] - e) / (0.015 * dv)
            }
        }

        let wt1Series = ema(ci, period: averageLength)
        let wt1Plain = wt1Series.map { $0 ?? 0 }
        let wt2Series = sma(wt1Plain, period: 4)

        for i in 1..<n {
            guard let w1 = wt1Series[i], let w2 = wt2Series[i],
                  let pw1 = wt1Series[i - 1], let pw2 = wt2Series[i - 1] else { continue }
            let crossUp = pw1 <= pw2 && w1 > w2
            let crossDown = pw1 >= pw2 && w1 < w2
            let buySig = smartOnly ? (crossUp && w1 <= oversold) : crossUp
            let sellSig = smartOnly ? (crossDown && w1 >= overbought) : crossDown
            result[i] = WaveTrendPoint(
                wt1: w1,
                wt2: w2,
                histogram: w1 - w2,
                buySignal: buySig,
                sellSignal: sellSig
            )
        }
        return result
    }

    /// Z-Score distance from rolling VWAP: (Close - VWAP(len)) / StDev(Close, len).
    static func computeZVWAP(candles: [Candle], length: Int) -> [Double?] {
        let n = candles.count
        var result: [Double?] = Array(repeating: nil, count: n)
        guard n >= length else { return result }

        for i in (length - 1)..<n {
            var pvSum = 0.0
            var vSum = 0.0
            for j in (i - length + 1)...i {
                let vol = max(candles[j].volume, 1e-6)
                pvSum += candles[j].hlc3 * vol
                vSum += vol
            }
            let vwap = pvSum / max(vSum, 1e-6)
            var varSum = 0.0
            for j in (i - length + 1)...i {
                let d = candles[j].close - vwap
                varSum += d * d
            }
            let sd = sqrt(varSum / Double(length))
            if sd > 1e-9 {
                let z = (candles[i].close - vwap) / sd
                result[i] = max(-4.5, min(4.5, z))
            } else {
                result[i] = 0
            }
        }
        return result
    }

    /// Smoothed Heikin-Ashi trend bias (pre-EMA -> HA open/close -> post-EMA).
    static func computeHeikinAshiBias(candles: [Candle], preLength: Int, smoothLength: Int) -> [Bool?] {
        let n = candles.count
        guard n > preLength + smoothLength else { return Array(repeating: nil, count: n) }

        let eo = ema(candles.map(\.open), period: preLength)
        let eh = ema(candles.map(\.high), period: preLength)
        let el = ema(candles.map(\.low), period: preLength)
        let ec = ema(candles.map(\.close), period: preLength)

        var haOpen = [Double](repeating: 0, count: n)
        var haClose = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let o = eo[i] ?? candles[i].open
            let h = eh[i] ?? candles[i].high
            let l = el[i] ?? candles[i].low
            let c = ec[i] ?? candles[i].close
            haClose[i] = (o + h + l + c) * 0.25
            haOpen[i] = i == 0 ? (o + c) * 0.5 : (haOpen[i - 1] + haClose[i - 1]) * 0.5
        }

        let sOpen = ema(haOpen, period: smoothLength)
        let sClose = ema(haClose, period: smoothLength)
        var bias: [Bool?] = Array(repeating: nil, count: n)
        for i in 0..<n {
            if let so = sOpen[i], let sc = sClose[i] {
                bias[i] = sc >= so
            }
        }
        return bias
    }

    static func detectOscillatorDivergences(candles: [Candle], waveTrend: [WaveTrendPoint?]) -> [OscillatorDivergence] {
        let n = candles.count
        let piv = 4
        guard n > piv * 4 else { return [] }

        var lowPivots: [(idx: Int, price: Double, wt: Double)] = []
        var highPivots: [(idx: Int, price: Double, wt: Double)] = []

        for i in piv..<(n - piv) {
            guard let wt = waveTrend[i]?.wt1 else { continue }
            var isLow = true
            var isHigh = true
            for j in (i - piv)...(i + piv) where j != i {
                if let ow = waveTrend[j]?.wt1 {
                    if ow <= wt { isLow = false }
                    if ow >= wt { isHigh = false }
                }
            }
            if isLow && wt < -15 { lowPivots.append((i, candles[i].low, wt)) }
            if isHigh && wt > 15 { highPivots.append((i, candles[i].high, wt)) }
        }

        var divs: [OscillatorDivergence] = []
        if lowPivots.count >= 2 {
            for k in 1..<lowPivots.count {
                let p1 = lowPivots[k - 1]
                let p2 = lowPivots[k]
                if p2.idx - p1.idx <= 55 && p2.price < p1.price && p2.wt > p1.wt + 4.0 {
                    divs.append(OscillatorDivergence(id: divs.count, startIndex: p1.idx, endIndex: p2.idx, startWT: p1.wt, endWT: p2.wt, isBullish: true))
                }
            }
        }
        if highPivots.count >= 2 {
            for k in 1..<highPivots.count {
                let p1 = highPivots[k - 1]
                let p2 = highPivots[k]
                if p2.idx - p1.idx <= 55 && p2.price > p1.price && p2.wt < p1.wt - 4.0 {
                    divs.append(OscillatorDivergence(id: divs.count, startIndex: p1.idx, endIndex: p2.idx, startWT: p1.wt, endWT: p2.wt, isBullish: false))
                }
            }
        }
        return Array(divs.suffix(8))
    }

    // MARK: - 1. Market Structure 2.0 (Dual-Tier BOS/CHoCH/CHoCH+ & OB Pressure + RSI Div)

    static func detectDualTierStructureAndBlocks(
        candles: [Candle],
        internalLookback: Int,
        macroLookback: Int,
        maxActivePerSide: Int
    ) -> (breaks: [StructureBreak], blocks: [OrderBlockZone]) {
        let n = candles.count
        guard n > internalLookback * 3 else { return ([], []) }

        var breaks: [StructureBreak] = []
        var blocks: [OrderBlockZone] = []

        func scanTier(lookback: Int, isMacro: Bool) {
            guard n > lookback * 2 + 2 else { return }
            var lastSwingHigh: (idx: Int, price: Double)? = nil
            var lastSwingLow: (idx: Int, price: Double)? = nil
            var highBroken = false
            var lowBroken = false
            var trendBias = 0

            for i in lookback..<(n - lookback) {
                let h = candles[i].high
                let l = candles[i].low
                var isHigh = true
                var isLow = true
                for j in (i - lookback)...(i + lookback) where j != i {
                    // Tie-break flat tops/bottoms cleanly (left strict >, right >=) so equal highs/lows never erase pivots
                    if j < i {
                        if candles[j].high > h { isHigh = false }
                        if candles[j].low < l { isLow = false }
                    } else {
                        if candles[j].high >= h { isHigh = false }
                        if candles[j].low <= l { isLow = false }
                    }
                }
                if isHigh { lastSwingHigh = (i, h); highBroken = false }
                if isLow { lastSwingLow = (i, l); lowBroken = false }

                let cur = candles[i]
                if let sh = lastSwingHigh, !highBroken, cur.close > sh.price, i > sh.idx + 1 {
                    highBroken = true
                    let label: String
                    if trendBias == -1 { label = isMacro ? "CHoCH+" : "CHoCH" }
                    else { label = isMacro ? "BOS+" : "BOS" }
                    trendBias = 1
                    breaks.append(StructureBreak(id: breaks.count, index: i, fromIndex: sh.idx, price: sh.price, label: label, isBullish: true, isMacro: isMacro))

                    if !isMacro, let obIdx = ((sh.idx)..<i).reversed().first(where: { !candles[$0].isBullish }) {
                        let obC = candles[obIdx]
                        let mitigated = ((i + 1)..<n).contains(where: { candles[$0].close < obC.low })
                        let pressure = estimateBlockPressure(candles: candles, obIndex: obIdx, breakIndex: i, isBullish: true)
                        blocks.append(OrderBlockZone(
                            id: blocks.count,
                            startIndex: obIdx,
                            endIndex: n - 1,
                            top: obC.high,
                            bottom: obC.low,
                            isBullish: true,
                            mitigated: mitigated,
                            pressurePercent: pressure,
                            isSwing: isMacro
                        ))
                    }
                }

                if let sl = lastSwingLow, !lowBroken, cur.close < sl.price, i > sl.idx + 1 {
                    lowBroken = true
                    let label: String
                    if trendBias == 1 { label = isMacro ? "CHoCH+" : "CHoCH" }
                    else { label = isMacro ? "BOS+" : "BOS" }
                    trendBias = -1
                    breaks.append(StructureBreak(id: breaks.count, index: i, fromIndex: sl.idx, price: sl.price, label: label, isBullish: false, isMacro: isMacro))

                    if !isMacro, let obIdx = ((sl.idx)..<i).reversed().first(where: { candles[$0].isBullish }) {
                        let obC = candles[obIdx]
                        let mitigated = ((i + 1)..<n).contains(where: { candles[$0].close > obC.high })
                        let pressure = estimateBlockPressure(candles: candles, obIndex: obIdx, breakIndex: i, isBullish: false)
                        blocks.append(OrderBlockZone(
                            id: blocks.count,
                            startIndex: obIdx,
                            endIndex: n - 1,
                            top: obC.high,
                            bottom: obC.low,
                            isBullish: false,
                            mitigated: mitigated,
                            pressurePercent: pressure,
                            isSwing: isMacro
                        ))
                    }
                }
            }
        }

        scanTier(lookback: internalLookback, isMacro: false)
        scanTier(lookback: macroLookback, isMacro: true)

        // Keep recent active OBs per side (plus a couple mitigated for historical context)
        let bullActive = blocks.filter { $0.isBullish && !$0.mitigated }.suffix(maxActivePerSide)
        let bearActive = blocks.filter { !$0.isBullish && !$0.mitigated }.suffix(maxActivePerSide)
        let recentMitigated = blocks.filter { $0.mitigated }.suffix(3)
        let finalBlocks = Array(bullActive) + Array(bearActive) + Array(recentMitigated)

        return (Array(breaks.sorted { $0.index < $1.index }.suffix(16)), finalBlocks)
    }

    /// Clean-room estimate of directional buyer/seller volume share (0–100%) inside an OB displacement leg.
    private static func estimateBlockPressure(candles: [Candle], obIndex: Int, breakIndex: Int, isBullish: Bool) -> Double {
        let start = max(0, obIndex)
        let end = min(candles.count - 1, max(obIndex + 1, breakIndex))
        var bullVol = 0.0
        var bearVol = 0.0
        for j in start...end {
            let c = candles[j]
            let range = max(c.range, 1e-6)
            let closePos = max(0.05, min(0.95, (c.close - c.low) / range))
            bullVol += c.volume * closePos
            bearVol += c.volume * (1.0 - closePos)
        }
        let total = max(bullVol + bearVol, 1e-6)
        return ((isBullish ? bullVol : bearVol) / total) * 100.0
    }

    static func detectRSIDivergences(candles: [Candle], rsi: [Double?], pivot: Int) -> [RSIDivergence] {
        let n = candles.count
        let p = max(3, min(10, pivot))
        guard n > p * 4 else { return [] }

        var lows: [(idx: Int, price: Double, rsi: Double)] = []
        var highs: [(idx: Int, price: Double, rsi: Double)] = []

        for i in p..<(n - p) {
            guard let rv = rsi[i] else { continue }
            var isLow = true
            var isHigh = true
            for j in (i - p)...(i + p) where j != i {
                if j < i {
                    if candles[j].low < candles[i].low { isLow = false }
                    if candles[j].high > candles[i].high { isHigh = false }
                } else {
                    if candles[j].low <= candles[i].low { isLow = false }
                    if candles[j].high >= candles[i].high { isHigh = false }
                }
            }
            if isLow && rv <= 45 { lows.append((i, candles[i].low, rv)) }
            if isHigh && rv >= 55 { highs.append((i, candles[i].high, rv)) }
        }

        var divs: [RSIDivergence] = []
        if lows.count >= 2 {
            for k in 1..<lows.count {
                let a = lows[k - 1]; let b = lows[k]
                if b.idx - a.idx <= 60 && b.price < a.price && b.rsi > a.rsi + 2.5 {
                    divs.append(RSIDivergence(id: divs.count, startIndex: a.idx, endIndex: b.idx, startPrice: a.price, endPrice: b.price, isBullish: true, label: "Bull Div"))
                }
            }
        }
        if highs.count >= 2 {
            for k in 1..<highs.count {
                let a = highs[k - 1]; let b = highs[k]
                if b.idx - a.idx <= 60 && b.price > a.price && b.rsi < a.rsi - 2.5 {
                    divs.append(RSIDivergence(id: divs.count, startIndex: a.idx, endIndex: b.idx, startPrice: a.price, endPrice: b.price, isBullish: false, label: "Bear Div"))
                }
            }
        }
        return Array(divs.suffix(6))
    }

    // MARK: - 2. Order Flow & Delta (BuAx+/BuAx-/BeAx+/BeAx-, Protected Levels, Volume Zones, FVGs)

    static func detectFVGs(candles: [Candle]) -> [FairValueGap] {
        let n = candles.count
        guard n >= 5 else { return [] }
        var fvgs: [FairValueGap] = []
        for i in 2..<n {
            let c0 = candles[i - 2]
            let c2 = candles[i]
            if c2.low > c0.high && (c2.low - c0.high) > max(c0.range * 0.06, 1e-6) {
                let filled = ((i + 1)..<n).contains(where: { candles[$0].low <= c0.high })
                fvgs.append(FairValueGap(id: fvgs.count, startIndex: i - 1, top: c2.low, bottom: c0.high, isBullish: true, filled: filled))
            } else if c2.high < c0.low && (c0.low - c2.high) > max(c0.range * 0.06, 1e-6) {
                let filled = ((i + 1)..<n).contains(where: { candles[$0].high >= c0.low })
                fvgs.append(FairValueGap(id: fvgs.count, startIndex: i - 1, top: c0.low, bottom: c2.high, isBullish: false, filled: filled))
            }
        }
        let openFVGs = Array(fvgs.filter { !$0.filled }.suffix(8))
        if !openFVGs.isEmpty { return openFVGs }
        return Array(fvgs.suffix(6))
    }

    /// Clean-room Accelerator Engine emitting BuAx+/BuAx-/BeAx+/BeAx- markers + Wickless institutional stars.
    static func detectAccelerators(
        candles: [Candle],
        rangeFactor: Double,
        deltaFactor: Double,
        plusOnly: Bool
    ) -> [AcceleratorMarker] {
        let n = candles.count
        guard n >= 22 else { return [] }
        var markers: [AcceleratorMarker] = []

        for i in 20..<n {
            let window = candles[(i - 20)..<i]
            let avgRange = max(window.reduce(0.0) { $0 + $1.range } / 20.0, 1e-6)
            let avgAbsDelta = max(window.reduce(0.0) { acc, bar in
                let closePos = (bar.close - bar.low) / max(bar.range, 1e-6)
                let estDelta = abs((closePos * 2.0 - 1.0) * max(bar.volume, 1.0))
                return acc + estDelta
            } / 20.0, 1e-6)

            let c = candles[i]
            let body = abs(c.close - c.open)
            let closePos = (c.close - c.low) / max(c.range, 1e-6)
            let estAbsDelta = abs((closePos * 2.0 - 1.0) * max(c.volume, 1.0))
            let deltaRatio = estAbsDelta / avgAbsDelta

            let lowerWick = c.bodyBottom - c.low
            let upperWick = c.high - c.bodyTop
            let wickless = c.isBullish ? (lowerWick <= c.range * 0.10) : (upperWick <= c.range * 0.10)

            let strongRange = c.range >= avgRange * max(1.1, rangeFactor)
            let strongDelta = deltaRatio >= max(1.1, deltaFactor)
            let strongBody = body >= c.range * 0.45
            let isAx = strongBody && ((strongRange && deltaRatio >= 1.05) || (strongDelta && c.range >= avgRange * 1.15))

            if isAx {
                let isPlus = wickless || (c.range >= avgRange * (rangeFactor + 0.40) && deltaRatio >= deltaFactor + 0.35)
                if !plusOnly || isPlus {
                    markers.append(AcceleratorMarker(
                        id: markers.count,
                        index: i,
                        isBullish: c.isBullish,
                        isPlus: isPlus,
                        isWickless: wickless,
                        deltaRatio: deltaRatio
                    ))
                }
            }
        }
        return Array(markers.suffix(22))
    }

    static func detectProtectedLevels(candles: [Candle], lookback: Int) -> [ProtectedLevel] {
        let n = candles.count
        let lb = max(4, min(14, lookback))
        guard n > lb * 2 + 2 else { return [] }
        var levels: [ProtectedLevel] = []

        for i in lb..<(n - lb) {
            let h = candles[i].high
            let l = candles[i].low
            var isHigh = true
            var isLow = true
            for j in (i - lb)...(i + lb) where j != i {
                if j < i {
                    if candles[j].high > h { isHigh = false }
                    if candles[j].low < l { isLow = false }
                } else {
                    if candles[j].high >= h { isHigh = false }
                    if candles[j].low <= l { isLow = false }
                }
            }
            if isHigh {
                let swept = ((i + 1)..<n).contains(where: { candles[$0].high > h })
                if !swept {
                    levels.append(ProtectedLevel(id: levels.count, startIndex: i, price: h, isHigh: true))
                }
            }
            if isLow {
                let swept = ((i + 1)..<n).contains(where: { candles[$0].low < l })
                if !swept {
                    levels.append(ProtectedLevel(id: levels.count, startIndex: i, price: l, isHigh: false))
                }
            }
        }
        let highs = levels.filter(\.isHigh).suffix(2)
        let lows = levels.filter { !$0.isHigh }.suffix(2)
        return Array(highs) + Array(lows)
    }

    static func detectVolumeZones(candles: [Candle], threshold: Double, avgLen: Int, maxZones: Int) -> [VolumeZone] {
        let n = candles.count
        guard n > avgLen + 2 else { return [] }
        var zones: [VolumeZone] = []

        for i in avgLen..<n {
            let avgVol = max(candles[(i - avgLen)..<i].reduce(0.0) { $0 + $1.volume } / Double(avgLen), 1e-6)
            let mult = candles[i].volume / avgVol
            if mult >= threshold {
                let c = candles[i]
                let mid = (c.bodyTop + c.bodyBottom) * 0.5
                // Dedupe within 0.1% price
                let duplicate = zones.contains(where: { abs((($0.top + $0.bottom) * 0.5) - mid) / max(mid, 1e-6) < 0.001 })
                if !duplicate {
                    zones.append(VolumeZone(
                        id: zones.count,
                        startIndex: i,
                        top: c.bodyTop,
                        bottom: c.bodyBottom,
                        isBullish: c.isBullish,
                        volumeMultiple: mult
                    ))
                }
            }
        }
        return Array(zones.suffix(maxZones))
    }

    // MARK: - 3. Reversal & ATR Targets (BB Width Gate + RSI 25/72 + ATR Targets)

    static func detectReversalTargets(
        candles: [Candle],
        bbUpper: [Double?],
        bbMiddle: [Double?],
        bbLower: [Double?],
        rsi: [Double?],
        atr: [Double?],
        config: IndicatorConfig
    ) -> [ReversalSetupSignal] {
        let n = candles.count
        guard n >= 25 else { return [] }
        var signals: [ReversalSetupSignal] = []
        var lastSignalIdx = -10

        for i in 22..<n {
            guard i - lastSignalIdx >= 6,
                  let upper = bbUpper[i], let mid = bbMiddle[i], let lower = bbLower[i],
                  let rv = rsi[i], let av = atr[i], av > 0, mid > 0 else { continue }

            let prevRSI = rsi[i - 1] ?? rv
            let prevBar = candles[i - 1]

            // Bollinger Band width filter
            let bbWidth = (upper - lower) / mid
            guard bbWidth >= config.revBBThreshold else { continue }

            let c = candles[i]
            let stopDist = av * max(0.5, config.revATRStopMult)

            let touchedLow = (c.low <= lower) || (prevBar.low <= (bbLower[i - 1] ?? lower))
            let touchedHigh = (c.high >= upper) || (prevBar.high >= (bbUpper[i - 1] ?? upper))

            if touchedLow && (rv <= config.revRSILower || prevRSI <= config.revRSILower) && c.isBullish {
                let entry = c.close
                signals.append(ReversalSetupSignal(
                    id: signals.count,
                    index: i,
                    isBullish: true,
                    entry: entry,
                    stopLoss: entry - stopDist,
                    tp1: entry + stopDist * config.revTP1,
                    tp2: entry + stopDist * config.revTP2,
                    tp3: entry + stopDist * config.revTP3
                ))
                lastSignalIdx = i
            } else if touchedHigh && (rv >= config.revRSIUpper || prevRSI >= config.revRSIUpper) && !c.isBullish {
                let entry = c.close
                signals.append(ReversalSetupSignal(
                    id: signals.count,
                    index: i,
                    isBullish: false,
                    entry: entry,
                    stopLoss: entry + stopDist,
                    tp1: entry - stopDist * config.revTP1,
                    tp2: entry - stopDist * config.revTP2,
                    tp3: entry - stopDist * config.revTP3
                ))
                lastSignalIdx = i
            }
        }
        return Array(signals.suffix(6))
    }

    // MARK: - 5. Sideway Detector Scalp Zone Engine

    /// Clean-room Scalp Zone detector:
    /// 1. Impulse >= scMove x average swing over scMoveBars
    /// 2. Followed by >= scQuietBars candles shrinking to <= scSlowPct% of the impulse
    /// 3. Anchored to an active Order Block with directional pressure >= scSharePct%
    static func detectScalpZones(
        candles: [Candle],
        atr: [Double?],
        orderBlocks: [OrderBlockZone],
        config: IndicatorConfig
    ) -> [ScalpZoneBox] {
        let n = candles.count
        let moveBars = max(6, config.sidewayScMoveBars)
        let quietNeed = max(2, config.sidewayScQuietBars)
        guard n > moveBars + quietNeed + 2 else { return [] }

        var zones: [ScalpZoneBox] = []
        var lastZoneEnd = -20

        for i in moveBars..<(n - quietNeed) {
            guard i - lastZoneEnd >= 10 else { continue }
            let avgSwing = max(candles[(i - moveBars)..<i].reduce(0.0) { $0 + $1.range } / Double(moveBars), 1e-6)
            let impulse = candles[i]
            guard impulse.range >= avgSwing * config.sidewayScMove else { continue }

            let maxQuietRange = impulse.range * (config.sidewayScSlowPct / 100.0)
            var quietCount = 0
            for j in (i + 1)...min(n - 1, i + quietNeed + 4) {
                if candles[j].range <= maxQuietRange {
                    quietCount += 1
                } else {
                    break
                }
            }
            guard quietCount >= quietNeed else { continue }

            let av = atr[i] ?? avgSwing
            let zoneEnd = min(n - 1, i + quietCount)
            let zoneSlice = candles[(i + 1)...zoneEnd]
            let zHigh = (zoneSlice.map(\.high).max() ?? impulse.high) + av * config.sidewayScNearATR * 0.5
            let zLow = (zoneSlice.map(\.low).min() ?? impulse.low) - av * config.sidewayScNearATR * 0.5

            // Compute directional share inside the impulse + quiet cluster
            let pressure = estimateBlockPressure(candles: candles, obIndex: i, breakIndex: zoneEnd, isBullish: impulse.isBullish)
            guard pressure >= config.sidewayScSharePct || orderBlocks.contains(where: { !$0.mitigated && $0.pressurePercent >= config.sidewayScSharePct }) else {
                continue
            }

            zones.append(ScalpZoneBox(
                id: zones.count,
                startIndex: i + 1,
                endIndex: min(n - 1, zoneEnd + 12),
                top: zHigh,
                bottom: zLow,
                isBullish: impulse.isBullish,
                pressurePercent: pressure,
                quietCount: quietCount
            ))
            lastZoneEnd = zoneEnd
        }
        return Array(zones.suffix(5))
    }

    // MARK: - 4. Session Toolkits (Volume Profile & Camarilla / Fibonacci P2–P5 Pivots)

    static func computeVolumeProfile(
        candles: ArraySlice<Candle>,
        binCount: Int,
        valueAreaPercent: Double
    ) -> VolumeProfileResult? {
        guard !candles.isEmpty, binCount >= 4 else { return nil }
        let minP = candles.map(\.low).min() ?? 0
        let maxP = candles.map(\.high).max() ?? 1
        let span = max(maxP - minP, 1e-6)
        let step = span / Double(binCount)

        var buys = [Double](repeating: 0, count: binCount)
        var sells = [Double](repeating: 0, count: binCount)

        for c in candles {
            let loIdx = max(0, min(binCount - 1, Int((c.low - minP) / step)))
            let hiIdx = max(0, min(binCount - 1, Int((c.high - minP) / step)))
            let count = Double(max(1, hiIdx - loIdx + 1))
            let perBin = c.volume / count
            for b in loIdx...hiIdx {
                if c.isBullish { buys[b] += perBin } else { sells[b] += perBin }
            }
        }

        var bins: [VolumeProfileBin] = []
        bins.reserveCapacity(binCount)
        var pocIdx = 0
        var maxVol = 0.0
        var totalVol = 0.0

        for b in 0..<binCount {
            let bin = VolumeProfileBin(
                low: minP + Double(b) * step,
                high: minP + Double(b + 1) * step,
                buyVolume: buys[b],
                sellVolume: sells[b]
            )
            bins.append(bin)
            totalVol += bin.totalVolume
            if bin.totalVolume > maxVol {
                maxVol = bin.totalVolume
                pocIdx = b
            }
        }

        let targetVol = totalVol * (valueAreaPercent / 100.0)
        var vaVol = bins[pocIdx].totalVolume
        var lo = pocIdx
        var hi = pocIdx
        while vaVol < targetVol && (lo > 0 || hi < binCount - 1) {
            let upVol = hi + 1 < binCount ? bins[hi + 1].totalVolume : -1
            let dnVol = lo - 1 >= 0 ? bins[lo - 1].totalVolume : -1
            if upVol >= dnVol { hi += 1; vaVol += bins[hi].totalVolume }
            else { lo -= 1; vaVol += bins[lo].totalVolume }
        }

        return VolumeProfileResult(
            bins: bins,
            pocPrice: (bins[pocIdx].low + bins[pocIdx].high) * 0.5,
            vahPrice: bins[hi].high,
            valPrice: bins[lo].low,
            maxVolume: max(maxVol, 1.0)
        )
    }

    static func computePivots(candles: [Candle], kind: PivotKind) -> PivotLevels? {
        guard candles.count >= 24 else { return nil }
        let slice = candles.suffix(48).prefix(24)
        guard let h = slice.map(\.high).max(),
              let l = slice.map(\.low).min(),
              let c = slice.last?.close else { return nil }
        let r = h - l
        let p = (h + l + c) / 3.0

        switch kind {
        case .camarilla:
            let r4 = c + r * 1.1 / 2.0
            let r5 = (h / max(l, 1e-6)) * c
            let s4 = c - r * 1.1 / 2.0
            let s5 = c - (r5 - c)
            return PivotLevels(
                kind: kind,
                pivot: p,
                r1: c + r * 1.1 / 12.0,
                r2: c + r * 1.1 / 6.0,
                r3: c + r * 1.1 / 4.0,
                r4: r4,
                r5: r5,
                s1: c - r * 1.1 / 12.0,
                s2: c - r * 1.1 / 6.0,
                s3: c - r * 1.1 / 4.0,
                s4: s4,
                s5: s5
            )
        case .fibonacci:
            return PivotLevels(
                kind: kind,
                pivot: p,
                r1: p + r * 0.382,
                r2: p + r * 0.618,
                r3: p + r * 1.000,
                r4: p + r * 1.272,
                r5: p + r * 1.618,
                s1: p - r * 0.382,
                s2: p - r * 0.618,
                s3: p - r * 1.000,
                s4: p - r * 1.272,
                s5: p - r * 1.618
            )
        }
    }
}
