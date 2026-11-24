import SwiftUI

struct SampleAccountView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Paper Desk Account")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Live-feed execution with automatic SL/TP fills, pending Limit/Stop orders, and instant Journal logging.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                }
                Spacer()
                if !store.samplePositions.isEmpty {
                    Button("Close All Positions") {
                        store.closeAllSamplePositions()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6.5)
                    .background(t.bear, in: RoundedRectangle(cornerRadius: t.radiusControl))
                }
            }

            // Unified Hairline-Divided Metric Strip
            HStack(spacing: 0) {
                kpiCell("BALANCE", String(format: "$%.2f", store.sampleBalance), t.primaryText, theme: t)
                Rectangle().fill(t.border).frame(width: 1)
                kpiCell("EQUITY", String(format: "$%.2f", store.sampleEquity), t.accent, theme: t)
                Rectangle().fill(t.border).frame(width: 1)
                kpiCell("FLOATING PNL", String(format: "%@$%.2f", store.floatingPnL >= 0 ? "+" : "-", abs(store.floatingPnL)), store.floatingPnL >= 0 ? t.bull : t.bear, theme: t)
                Rectangle().fill(t.border).frame(width: 1)
                kpiCell("OPEN POSITIONS", "\(store.samplePositions.count)", t.primaryText, theme: t)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
            .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))

            // Open Positions Table
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("OPEN POSITIONS (\(store.samplePositions.count))")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(t.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(t.chromeBg)
                .overlay(alignment: .bottom) { Rectangle().fill(t.border).frame(height: 1) }

                if store.samplePositions.isEmpty {
                    Text("No open paper positions. Open the Desk drawer on Terminal to place Market, Limit, or Stop orders.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                        .padding(18)
                } else {
                    ForEach(store.samplePositions) { pos in
                        let refPrice = (pos.instrument == store.instrument) ? store.lastPrice : pos.instrument.basePrice
                        let pnl = pos.floatingPnL(currentPrice: refPrice)
                        HStack(spacing: 12) {
                            Text(pos.isBuy ? "BUY" : "SELL")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background((pos.isBuy ? t.bull : t.bear).opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(pos.isBuy ? t.bull : t.bear)

                            Text(pos.instrument.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(t.primaryText)
                                .frame(width: 86, alignment: .leading)

                            Text(String(format: "%.2f lots", pos.lots))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(t.secondaryText)

                            Text("Entry \(pos.instrument.formatPrice(pos.entryPrice))")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(t.primaryText)

                            if let sl = pos.stopLoss {
                                Text("SL \(pos.instrument.formatPrice(sl))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(t.bear)
                            }
                            if let tp = pos.takeProfit {
                                Text("TP \(pos.instrument.formatPrice(tp))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(t.bull)
                            }

                            Spacer()

                            Text(String(format: "%@$%.2f", pnl >= 0 ? "+" : "-", abs(pnl)))
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(pnl >= 0 ? t.bull : t.bear)

                            Button("50%") {
                                store.partialClosePaperPosition(id: pos.id, fraction: 0.5)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(t.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: t.radiusSharp))

                            Button("BE") {
                                store.movePaperPositionToBreakeven(id: pos.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(t.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(t.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: t.radiusSharp))

                            Button("Close") {
                                store.closeSamplePosition(id: pos.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(t.softSurface, in: RoundedRectangle(cornerRadius: t.radiusSharp))
                            .overlay(RoundedRectangle(cornerRadius: t.radiusSharp).stroke(t.border, lineWidth: 0.75))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(t.border.opacity(0.55)).frame(height: 0.5) }
                    }
                }
            }
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
            .clipShape(RoundedRectangle(cornerRadius: t.radiusPanel))
            .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))

            if !store.paperPendingOrders.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PENDING LIMIT / STOP ORDERS (\(store.paperPendingOrders.count))")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(t.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.chromeBg)
                        .overlay(alignment: .bottom) { Rectangle().fill(t.border).frame(height: 1) }

                    ForEach(store.paperPendingOrders) { ord in
                        HStack(spacing: 12) {
                            Text("\(ord.isBuy ? "BUY" : "SELL") \(ord.kind.rawValue.uppercased())")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(t.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(t.amber)

                            Text(ord.instrument.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(t.primaryText)

                            Text(String(format: "%.2f lots @ %@", ord.lots, ord.instrument.formatPrice(ord.entryPrice)))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(t.primaryText)

                            Spacer()

                            Button("Cancel") {
                                store.cancelPendingOrder(id: ord.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.bear)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9.5)
                        .overlay(alignment: .bottom) { Rectangle().fill(t.border.opacity(0.55)).frame(height: 0.5) }
                    }
                }
                .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
                .clipShape(RoundedRectangle(cornerRadius: t.radiusPanel))
                .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))
            }

            Spacer()
        }
        .padding(20)
        .background(t.canvasBg)
    }

    private func kpiCell(_ title: String, _ value: String, _ tint: Color, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(t.secondaryText)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
