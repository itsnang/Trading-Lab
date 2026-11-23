import SwiftUI

struct SampleAccountView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        let t = store.theme

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Paper Trading Account")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Practice risk sizing and execution on live or sample feeds with zero real-money risk. Closed trades auto-log to your Journal.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.secondaryText)
                }
                Spacer()
                if !store.samplePositions.isEmpty {
                    Button("Close All Positions") {
                        store.closeAllSamplePositions()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(t.bear, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 14) {
                kpiCard("BALANCE", String(format: "$%.2f", store.sampleBalance), t.primaryText, theme: t)
                kpiCard("EQUITY", String(format: "$%.2f", store.sampleEquity), t.accent, theme: t)
                kpiCard("FLOATING PNL", String(format: "%@$%.2f", store.floatingPnL >= 0 ? "+" : "-", abs(store.floatingPnL)), store.floatingPnL >= 0 ? t.bull : t.bear, theme: t)
                kpiCard("OPEN POSITIONS", "\(store.samplePositions.count)", t.amber, theme: t)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("OPEN POSITIONS")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.secondaryText)

                if store.samplePositions.isEmpty {
                    Text("No open paper positions. Click 'Trade' in the top bar on Terminal to size and place a Buy or Sell order.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.secondaryText)
                        .padding(.vertical, 24)
                } else {
                    ForEach(store.samplePositions) { pos in
                        let refPrice = (pos.instrument == store.instrument) ? store.lastPrice : pos.instrument.basePrice
                        let pnl = pos.floatingPnL(currentPrice: refPrice)
                        HStack(spacing: 14) {
                            Text(pos.isBuy ? "BUY" : "SELL")
                                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background((pos.isBuy ? t.bull : t.bear).opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(pos.isBuy ? t.bull : t.bear)

                            Text(pos.instrument.rawValue)
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(t.primaryText)
                                .frame(width: 90, alignment: .leading)

                            Text(String(format: "%.2f lots", pos.lots))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(t.secondaryText)

                            Text("Entry \(pos.instrument.formatPrice(pos.entryPrice))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(t.primaryText)

                            if let sl = pos.stopLoss {
                                Text("SL \(pos.instrument.formatPrice(sl))")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(t.bear)
                            }
                            if let tp = pos.takeProfit {
                                Text("TP \(pos.instrument.formatPrice(tp))")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(t.bull)
                            }

                            Spacer()

                            Text(String(format: "%@$%.2f", pnl >= 0 ? "+" : "-", abs(pnl)))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(pnl >= 0 ? t.bull : t.bear)

                            Button("Close & Log") {
                                store.closeSamplePosition(id: pos.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(t.primaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(t.softSurface, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.border, lineWidth: 0.8))
                        }
                        .padding(12)
                        .background(t.softSurface, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            .padding(18)
            .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))

            Spacer()
        }
        .padding(22)
        .background(t.canvasBg)
    }

    private func kpiCard(_ title: String, _ value: String, _ tint: Color, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
            Text(value).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))
    }
}
