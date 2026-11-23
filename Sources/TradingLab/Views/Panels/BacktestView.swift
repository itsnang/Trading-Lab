import SwiftUI

struct BacktestView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme
        let rep = store.backtestReport

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Causal Strategy Backtester — \(store.instrument.rawValue) (\(store.timeframe.rawValue))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Evaluates your 4-stage rules bar-by-bar on \(store.dataMode.rawValue) candles (\(store.visibleSeries.count) bars) with zero lookahead.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.secondaryText)
                }
                Spacer()
                Toggle("Plot Signals on Chart", isOn: $store.showBacktestSignalsOnChart)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 14) {
                tuningControl("Target R:R", value: $store.strategyConfig.riskReward, range: 1.0...5.0, step: 0.5, fmt: "%.1fR", theme: t)
                tuningControl("Risk / Trade", value: $store.strategyConfig.riskPercent, range: 0.25...3.0, step: 0.25, fmt: "%.2f%%", theme: t)
                tuningControl("ATR Tolerance", value: $store.strategyConfig.nearATR, range: 0.2...1.5, step: 0.1, fmt: "%.1fx", theme: t)
                tuningIntControl("Expiry Bars", value: $store.strategyConfig.expiryBars, range: 5...60, theme: t)
            }
            .padding(14)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))

            HStack(spacing: 12) {
                kpi("TRADES", "\(rep.trades.count)", t.primaryText, theme: t)
                kpi("WIN RATE", String(format: "%.1f%%", rep.winRate), rep.winRate >= 45 ? t.bull : t.amber, theme: t)
                kpi("PROFIT FACTOR", String(format: "%.2f", rep.profitFactor), rep.profitFactor >= 1.2 ? t.accent : t.amber, theme: t)
                kpi("NET R", String(format: "%+.2fR", rep.totalR), rep.totalR >= 0 ? t.bull : t.bear, theme: t)
                kpi("MAX DD", String(format: "%.1f%%", rep.maxDrawdownPct), rep.maxDrawdownPct <= 8 ? t.primaryText : t.bear, theme: t)
                kpi("END EQUITY", String(format: "$%.0f", rep.endingBalance), rep.endingBalance >= rep.startingBalance ? t.bull : t.bear, theme: t)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EQUITY CURVE ($10,000 START)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.secondaryText)

                Canvas { ctx, size in
                    let curve = rep.equityCurve
                    guard curve.count >= 2 else { return }
                    let lo = (curve.min() ?? 9500) * 0.995
                    let hi = (curve.max() ?? 10500) * 1.005
                    let span = max(hi - lo, 1.0)
                    let baseY = size.height * CGFloat(1.0 - (rep.startingBalance - lo) / span)

                    var ref = Path()
                    ref.move(to: CGPoint(x: 0, y: baseY)); ref.addLine(to: CGPoint(x: size.width, y: baseY))
                    ctx.stroke(ref, with: .color(t.border), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    var line = Path()
                    for (idx, val) in curve.enumerated() {
                        let x = size.width * CGFloat(idx) / CGFloat(curve.count - 1)
                        let y = size.height * CGFloat(1.0 - (val - lo) / span)
                        if idx == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(line, with: .color(rep.endingBalance >= rep.startingBalance ? t.bull : t.bear), lineWidth: 2.2)
                }
                .frame(height: 115)
            }
            .padding(16)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Text("SIMULATED TRADES (\(rep.trades.count))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.secondaryText)

                if rep.trades.isEmpty {
                    Text("No trades triggered with current parameters on this window. Try adjusting ATR Tolerance or ADX threshold in Bot Studio.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.secondaryText)
                        .padding(.vertical, 16)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(rep.trades.reversed()) { tr in
                                HStack(spacing: 12) {
                                    Text(tr.isBuy ? "LONG" : "SHORT")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background((tr.isBuy ? t.bull : t.bear).opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                                        .foregroundStyle(tr.isBuy ? t.bull : t.bear)

                                    Text(tr.outcome)
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(tr.outcome == "TP" ? t.bull : (tr.outcome == "SL" ? t.bear : t.amber))
                                        .frame(width: 34)

                                    Text("\(store.instrument.formatPrice(tr.entryPrice)) → \(store.instrument.formatPrice(tr.exitPrice))")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(t.primaryText)

                                    Text(tr.reason)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(t.secondaryText)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(String(format: "%+.2fR", tr.rMultiple))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(tr.rMultiple >= 0 ? t.bull : t.bear)

                                    Text(String(format: "%@$%.2f", tr.pnlUSD >= 0 ? "+" : "-", abs(tr.pnlUSD)))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(t.primaryText)
                                        .frame(width: 82, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))
        }
        .padding(22)
        .background(t.canvasBg)
    }

    private func kpi(_ title: String, _ value: String, _ tint: Color, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
            Text(value).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.cardBg, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(t.border, lineWidth: 1))
    }

    private func tuningControl(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, fmt: String, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.secondaryText)
                Spacer()
                Text(String(format: fmt, value.wrappedValue)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(t.accent)
            }
            Slider(value: value, in: range, step: step)
        }
        .frame(maxWidth: .infinity)
    }

    private func tuningIntControl(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.secondaryText)
                Spacer()
                Text("\(value.wrappedValue)").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(t.accent)
            }
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
        .frame(maxWidth: .infinity)
    }
}
