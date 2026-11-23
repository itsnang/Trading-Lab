import SwiftUI

struct OscillatorPaneView: View {
    @EnvironmentObject var store: WorkspaceStore
    private let rightAxisWidth: CGFloat = 78

    var body: some View {
        let t = store.theme
        let cfg = store.indicatorConfig

        GeometryReader { geo in
            let plotWidth = max(100, geo.size.width - rightAxisWidth)
            let plotHeight = max(40, geo.size.height - 24)
            let candles = store.visibleSeries
            let count = max(1, candles.count)
            let vis = max(14.0, store.visibleCandleCount)
            let endIdxFloat = Double(count - 1) + store.rightOffsetBars
            let startIdxFloat = endIdxFloat - vis
            let stepX = plotWidth / CGFloat(vis)
            let first = max(0, min(count - 1, Int(floor(startIdxFloat))))
            let last = max(first, min(count - 1, Int(ceil(endIdxFloat))))

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    switch cfg.oscillatorMode {
                    case .waveTrend:
                        drawWaveTrendAndZVWAP(
                            ctx: &ctx,
                            size: size,
                            plotWidth: plotWidth,
                            plotHeight: plotHeight,
                            startIdxFloat: startIdxFloat,
                            stepX: stepX,
                            first: first,
                            last: last,
                            theme: t
                        )
                    case .rsi:
                        drawRSI(
                            ctx: &ctx,
                            size: size,
                            plotWidth: plotWidth,
                            plotHeight: plotHeight,
                            startIdxFloat: startIdxFloat,
                            stepX: stepX,
                            first: first,
                            last: last,
                            theme: t
                        )
                    }
                }
                .background(t.chartBg)

                HStack(spacing: 8) {
                    Text(cfg.oscillatorMode == .waveTrend
                         ? "Momentum Oscillator · WT (\(cfg.wtChannelLength),\(cfg.wtAverageLength))"
                         : "Momentum Oscillator · RSI (\(cfg.rsiLength))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.primaryText)

                    if cfg.oscillatorMode == .waveTrend {
                        if let lastWT = store.computed.waveTrend.last.flatMap({ $0 }) {
                            Text(String(format: "WT1 %.1f  WT2 %.1f", lastWT.wt1, lastWT.wt2))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(t.accent)
                        }
                        if cfg.oscShowZVWAP {
                            Text(String(format: "ZVWAP %+.2fσ", store.computed.lastZVWAP))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.purple)
                        }
                        if cfg.oscShowHABias, let ha = store.computed.haBiasBullish.last.flatMap({ $0 }) {
                            Text(ha ? "HA Bull" : "HA Bear")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background((ha ? t.bull : t.bear).opacity(0.14), in: Capsule())
                                .foregroundStyle(ha ? t.bull : t.bear)
                        }
                    } else {
                        Text(String(format: "%.1f", store.computed.lastRSI))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple)
                    }

                    Button {
                        store.settingsStudyKind = .momentumOscillator
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10.5))
                            .foregroundStyle(t.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 5)
            }
        }
        .frame(height: store.oscillatorHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }

    private func drawWaveTrendAndZVWAP(
        ctx: inout GraphicsContext,
        size: CGSize,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        startIdxFloat: Double,
        stepX: CGFloat,
        first: Int,
        last: Int,
        theme t: AppTheme
    ) {
        let cfg = store.indicatorConfig
        let minV = -85.0
        let maxV = 85.0
        let topPad: CGFloat = 20
        func yFor(_ v: Double) -> CGFloat {
            let norm = (v - minV) / (maxV - minV)
            return topPad + plotHeight * CGFloat(1.0 - norm)
        }

        // OB1/OB2 (+60/+53) and OS1/OS2 (-60/-53) shaded exhaustion zones
        let obZone = CGRect(x: 0, y: yFor(60), width: plotWidth, height: max(1, yFor(cfg.wtOverbought) - yFor(60)))
        let osZone = CGRect(x: 0, y: yFor(cfg.wtOversold), width: plotWidth, height: max(1, yFor(-60) - yFor(cfg.wtOversold)))
        ctx.fill(Path(obZone), with: .color(t.bear.opacity(0.10)))
        ctx.fill(Path(osZone), with: .color(t.bull.opacity(0.10)))

        for (val, col) in [(60.0, t.bear.opacity(0.45)), (cfg.wtOverbought, t.bear.opacity(0.32)), (0.0, t.border), (cfg.wtOversold, t.bull.opacity(0.32)), (-60.0, t.bull.opacity(0.45))] {
            let y = yFor(val)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 0.9, dash: val == 0 ? [] : [3, 3]))
            if val == cfg.wtOverbought || val == 0 || val == cfg.wtOversold {
                ctx.draw(Text(String(format: "%.0f", val)).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(t.secondaryText), at: CGPoint(x: plotWidth + rightAxisWidth * 0.5, y: y))
            }
        }

        // Smoothed Heikin-Ashi Trend Ribbon along the bottom of the oscillator pane
        if cfg.oscShowHABias && !store.computed.haBiasBullish.isEmpty {
            let haSeries = store.computed.haBiasBullish
            let hi = min(haSeries.count - 1, last)
            let ribbonY = topPad + plotHeight - 3
            let segW = max(1.5, stepX + 0.5)
            for i in first...hi {
                guard let bull = haSeries[i] else { continue }
                let x = CGFloat(Double(i) - startIdxFloat) * stepX
                ctx.fill(Path(CGRect(x: x - segW * 0.5, y: ribbonY, width: segW, height: 3.5)), with: .color((bull ? t.bull : t.bear).opacity(0.75)))
            }
        }

        let series = store.computed.waveTrend
        if !series.isEmpty {
            let zeroY = yFor(0)
            var wt1Path = Path()
            var wt2Path = Path()
            var started = false
            let hi = min(series.count - 1, last)

            for i in first...hi {
                guard let pt = series[i] else { started = false; continue }
                let x = CGFloat(Double(i) - startIdxFloat) * stepX
                let y1 = yFor(pt.wt1)
                let y2 = yFor(pt.wt2)
                let barW = max(1.5, stepX * 0.45)
                let hY = yFor(pt.histogram * 1.4)
                ctx.fill(Path(CGRect(x: x - barW * 0.5, y: min(zeroY, hY), width: barW, height: max(1, abs(hY - zeroY)))), with: .color((pt.histogram >= 0 ? t.accent : t.bear).opacity(0.24)))

                if !started {
                    wt1Path.move(to: CGPoint(x: x, y: y1)); wt2Path.move(to: CGPoint(x: x, y: y2)); started = true
                } else {
                    wt1Path.addLine(to: CGPoint(x: x, y: y1)); wt2Path.addLine(to: CGPoint(x: x, y: y2))
                }

                if pt.buySignal {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y1 - 4, width: 8, height: 8)), with: .color(t.bull))
                } else if pt.sellSignal {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y1 - 4, width: 8, height: 8)), with: .color(t.bear))
                }
            }
            ctx.stroke(wt1Path, with: .color(t.accent), lineWidth: 1.5)
            ctx.stroke(wt2Path, with: .color(t.amber), lineWidth: 1.2)
        }

        // ZVWAP overlay scaled onto the WaveTrend range (±3σ maps to ±60)
        if cfg.oscShowZVWAP && !store.computed.zvwap.isEmpty {
            let zSeries = store.computed.zvwap
            let hi = min(zSeries.count - 1, last)
            var zPath = Path()
            var zStarted = false
            for i in first...hi {
                guard let zv = zSeries[i] else { zStarted = false; continue }
                let pt = CGPoint(x: CGFloat(Double(i) - startIdxFloat) * stepX, y: yFor(zv * 20.0))
                if !zStarted { zPath.move(to: pt); zStarted = true } else { zPath.addLine(to: pt) }
            }
            ctx.stroke(zPath, with: .color(Color.purple.opacity(0.85)), style: StrokeStyle(lineWidth: 1.25, dash: [4, 2]))
        }

        // Regular Oscillator Divergences
        if cfg.oscShowDivergences {
            for div in store.computed.oscDivergences {
                let x1 = CGFloat(Double(div.startIndex) - startIdxFloat) * stepX
                let x2 = CGFloat(Double(div.endIndex) - startIdxFloat) * stepX
                guard x2 >= 0 && x1 <= plotWidth else { continue }
                let y1 = yFor(div.startWT)
                let y2 = yFor(div.endWT)
                let col = div.isBullish ? t.bull : t.bear
                var dp = Path(); dp.move(to: CGPoint(x: x1, y: y1)); dp.addLine(to: CGPoint(x: x2, y: y2))
                ctx.stroke(dp, with: .color(col), lineWidth: 1.6)
                ctx.draw(Text(div.isBullish ? "Bull" : "Bear").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: x2, y: div.isBullish ? y2 + 9 : y2 - 9))
            }
        }

        var sep = Path(); sep.move(to: CGPoint(x: plotWidth, y: 0)); sep.addLine(to: CGPoint(x: plotWidth, y: size.height))
        ctx.stroke(sep, with: .color(t.border), lineWidth: 1)
    }

    private func drawRSI(
        ctx: inout GraphicsContext,
        size: CGSize,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        startIdxFloat: Double,
        stepX: CGFloat,
        first: Int,
        last: Int,
        theme t: AppTheme
    ) {
        let topPad: CGFloat = 20
        func yFor(_ v: Double) -> CGFloat { topPad + plotHeight * CGFloat(1.0 - (v / 100.0)) }

        ctx.fill(Path(CGRect(x: 0, y: yFor(70), width: plotWidth, height: yFor(30) - yFor(70))), with: .color(Color.purple.opacity(0.08)))
        for lvl in [70.0, 50.0, 30.0] {
            let y = yFor(lvl)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(t.border), style: StrokeStyle(lineWidth: 0.9, dash: [3, 3]))
            ctx.draw(Text(String(format: "%.0f", lvl)).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(t.secondaryText), at: CGPoint(x: plotWidth + rightAxisWidth * 0.5, y: y))
        }

        let series = store.computed.rsi
        guard !series.isEmpty else { return }
        var path = Path()
        var started = false
        let hi = min(series.count - 1, last)
        for i in first...hi {
            guard let v = series[i] else { started = false; continue }
            let pt = CGPoint(x: CGFloat(Double(i) - startIdxFloat) * stepX, y: yFor(v))
            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(.purple), lineWidth: 1.6)

        var sep = Path(); sep.move(to: CGPoint(x: plotWidth, y: 0)); sep.addLine(to: CGPoint(x: plotWidth, y: size.height))
        ctx.stroke(sep, with: .color(t.border), lineWidth: 1)
    }
}
