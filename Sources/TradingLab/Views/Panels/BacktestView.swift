import SwiftUI

struct BacktestView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme
        let rep = store.backtestReport

        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Strategy Backtester")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(t.primaryText)
                        Text("\(store.instrument.rawValue) · \(store.timeframe.rawValue)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(t.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: t.radiusSharp))
                    }
                    Text("Causal 4-stage bar-by-bar simulation on \(store.visibleSeries.count) live bars — zero lookahead, conservative SL-first fills.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                }
                Spacer()
                HStack(spacing: 14) {
                    Toggle("Partial TP @ 1R + BE", isOn: $store.strategyConfig.partialTakeProfit)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11.5, weight: .medium))
                    Toggle("Plot Signals", isOn: $store.showBacktestSignalsOnChart)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11.5, weight: .medium))
                }
            }

            // Clean Parameter Strip (continuous sliders + fine step buttons, zero ugly macOS tick marks)
            HStack(spacing: 0) {
                tuningControl("TARGET R:R", value: $store.strategyConfig.riskReward, range: 1.0...5.0, step: 0.5, fmt: "%.1fR", theme: t)
                stripDivider(theme: t)
                tuningControl("RISK / TRADE", value: $store.strategyConfig.riskPercent, range: 0.25...3.0, step: 0.25, fmt: "%.2f%%", theme: t)
                stripDivider(theme: t)
                tuningControl("ATR TOLERANCE", value: $store.strategyConfig.nearATR, range: 0.2...1.5, step: 0.1, fmt: "%.1fx", theme: t)
                stripDivider(theme: t)
                tuningIntControl("EXPIRY BARS", value: $store.strategyConfig.expiryBars, range: 5...60, theme: t)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
            .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))

            // Unified Hairline-Divided KPI Metric Strip
            HStack(spacing: 0) {
                kpiCell("TRADES", "\(rep.trades.count)", t.primaryText, theme: t)
                stripDivider(theme: t)
                kpiCell("WIN RATE", String(format: "%.1f%%", rep.winRate), rep.winRate >= 45 ? t.bull : t.amber, theme: t)
                stripDivider(theme: t)
                kpiCell("PROFIT FACTOR", String(format: "%.2f", rep.profitFactor), rep.profitFactor >= 1.2 ? t.accent : t.amber, theme: t)
                stripDivider(theme: t)
                kpiCell("NET R", String(format: "%+.2fR", rep.totalR), rep.totalR >= 0 ? t.bull : t.bear, theme: t)
                stripDivider(theme: t)
                kpiCell("MAX DD", String(format: "%.1f%%", rep.maxDrawdownPct), rep.maxDrawdownPct <= 8 ? t.primaryText : t.bear, theme: t)
                stripDivider(theme: t)
                kpiCell("END EQUITY", String(format: "$%.0f", rep.endingBalance), rep.endingBalance >= rep.startingBalance ? t.bull : t.bear, theme: t)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
            .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))

            // Equity Curve with subtle shaded area
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EQUITY CURVE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(t.secondaryText)
                    Spacer()
                    Text(String(format: "START $%.0f  ·  END $%.0f", rep.startingBalance, rep.endingBalance))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(t.secondaryText)
                }

                Canvas { ctx, size in
                    let curve = rep.equityCurve
                    guard curve.count >= 2 else { return }
                    let lo = (curve.min() ?? 9500) * 0.995
                    let hi = (curve.max() ?? 10500) * 1.005
                    let span = max(hi - lo, 1.0)
                    let baseY = size.height * CGFloat(1.0 - (rep.startingBalance - lo) / span)
                    let lineColor = rep.endingBalance >= rep.startingBalance ? t.bull : t.bear

                    var ref = Path()
                    ref.move(to: CGPoint(x: 0, y: baseY))
                    ref.addLine(to: CGPoint(x: size.width, y: baseY))
                    ctx.stroke(ref, with: .color(t.border), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    var line = Path()
                    var area = Path()
                    for (idx, val) in curve.enumerated() {
                        let x = size.width * CGFloat(idx) / CGFloat(curve.count - 1)
                        let y = size.height * CGFloat(1.0 - (val - lo) / span)
                        if idx == 0 {
                            line.move(to: CGPoint(x: x, y: y))
                            area.move(to: CGPoint(x: x, y: baseY))
                            area.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            line.addLine(to: CGPoint(x: x, y: y))
                            area.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    area.addLine(to: CGPoint(x: size.width, y: baseY))
                    area.closeSubpath()

                    ctx.fill(area, with: .color(lineColor.opacity(t.isDark ? 0.12 : 0.08)))
                    ctx.stroke(line, with: .color(lineColor), lineWidth: 1.8)
                }
                .frame(height: 118)
            }
            .padding(14)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
            .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))

            // Tabular Trade Log
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("SIMULATED TRADES (\(rep.trades.count))")
                        .frame(width: 150, alignment: .leading)
                    Text("EXIT")
                        .frame(width: 44, alignment: .leading)
                    Text("ENTRY → EXIT")
                        .frame(width: 160, alignment: .leading)
                    Text("CONFLUENCE")
                    Spacer()
                    Text("R-MULT")
                        .frame(width: 68, alignment: .trailing)
                    Text("PNL")
                        .frame(width: 84, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(t.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(t.chromeBg)
                .overlay(alignment: .bottom) { Rectangle().fill(t.border).frame(height: 1) }

                if rep.trades.isEmpty {
                    Text("No trades triggered on this window. Adjust ATR Tolerance or tune your 4-stage rules in Bot Studio.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(rep.trades.reversed().enumerated()), id: \.element.id) { idx, tr in
                                HStack(spacing: 12) {
                                    HStack(spacing: 6) {
                                        Text(tr.isBuy ? "LONG" : "SHORT")
                                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2.5)
                                            .background((tr.isBuy ? t.bull : t.bear).opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                                            .foregroundStyle(tr.isBuy ? t.bull : t.bear)
                                    }
                                    .frame(width: 150, alignment: .leading)

                                    Text(tr.outcome)
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(tr.outcome.contains("TP") ? t.bull : (tr.outcome == "SL" ? t.bear : t.amber))
                                        .frame(width: 44, alignment: .leading)

                                    Text("\(store.instrument.formatPrice(tr.entryPrice)) → \(store.instrument.formatPrice(tr.exitPrice))")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(t.primaryText)
                                        .frame(width: 160, alignment: .leading)

                                    Text(tr.reason)
                                        .font(.system(size: 11))
                                        .foregroundStyle(t.secondaryText)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(String(format: "%+.2fR", tr.rMultiple))
                                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(tr.rMultiple >= 0 ? t.bull : t.bear)
                                        .frame(width: 68, alignment: .trailing)

                                    Text(String(format: "%@$%.2f", tr.pnlUSD >= 0 ? "+" : "-", abs(tr.pnlUSD)))
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(t.primaryText)
                                        .frame(width: 84, alignment: .trailing)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8.5)
                                .background(idx % 2 == 1 ? t.softSurface.opacity(0.35) : Color.clear)
                                .overlay(alignment: .bottom) { Rectangle().fill(t.border.opacity(0.5)).frame(height: 0.5) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
            .clipShape(RoundedRectangle(cornerRadius: t.radiusPanel))
            .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))
        }
        .padding(20)
        .background(t.canvasBg)
    }

    private func stripDivider(theme t: AppTheme) -> some View {
        Rectangle().fill(t.border).frame(width: 1)
    }

    private func kpiCell(_ title: String, _ value: String, _ tint: Color, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(t.secondaryText)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tuningControl(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, fmt: String, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(t.secondaryText)
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.accent)
            }
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = (($0 / step).rounded() * step) }
                ),
                in: range
            )
            .tint(t.accent)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
    }

    private func tuningIntControl(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(t.secondaryText)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.accent)
            }
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(t.accent)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
    }
}
