import SwiftUI

/// Clean, uncluttered Trade, Risk Sizing, Order Flow Tape & Alerts drawer (toggled from top bar).
private enum TicketOrderMode: String, CaseIterable, Identifiable {
    case market = "Market"
    case limit = "Limit"
    case stop = "Stop"
    var id: String { rawValue }
}

struct IndicatorDrawerView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var orderMode: TicketOrderMode = .market
    @State private var pendingEntryPrice: Double = 0

    var body: some View {
        let t = store.theme

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Risk-Sized Paper Desk Order Ticket
                panelCard(title: "PAPER DESK · RISK & ORDER TICKET", theme: t) {
                    VStack(spacing: 10) {
                        Picker("", selection: $orderMode) {
                            ForEach(TicketOrderMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: orderMode) { _, _ in
                            if pendingEntryPrice <= 0 { pendingEntryPrice = store.lastPrice }
                        }

                        if orderMode != .market {
                            numberField("Pending Entry Price", value: $pendingEntryPrice, theme: t)
                        }

                        HStack {
                            Toggle("Auto-Size by Risk %", isOn: $store.autoSizeByRisk)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(t.primaryText)
                            Spacer()
                            Text(String(format: "%.2f lots", store.effectiveOrderLots))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(t.accent)
                        }

                        HStack(spacing: 8) {
                            if store.autoSizeByRisk {
                                numberField("Risk %", value: $store.riskPercentPerTrade, theme: t)
                            } else {
                                numberField("Lots", value: $store.orderLots, theme: t)
                            }
                            numberField("SL (pips)", value: $store.orderStopPips, theme: t)
                            numberField("TP (pips)", value: $store.orderTakeProfitPips, theme: t)
                        }

                        let rr = store.orderStopPips > 0 ? (store.orderTakeProfitPips / store.orderStopPips) : 0
                        let riskUSD = store.orderStopPips * store.effectiveOrderLots * store.instrument.dollarPerPipPerLot
                        HStack {
                            Text(String(format: "Risk: $%.0f", riskUSD)).foregroundStyle(t.amber)
                            Spacer()
                            Text(String(format: "R:R 1:%.1f", rr)).foregroundStyle(rr >= 2.0 ? t.bull : t.secondaryText)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))

                        HStack(spacing: 8) {
                            orderActionButton(isBuy: false, color: t.bear)
                            orderActionButton(isBuy: true, color: t.bull)
                        }
                    }
                }

                // 2. Live Order Flow Pressure & Tape
                panelCard(title: "LIVE ORDER FLOW TAPE", theme: t) {
                    VStack(spacing: 8) {
                        let buyPct = store.buyPressurePercent
                        HStack {
                            Text(String(format: "BUY %.0f%%", buyPct)).foregroundStyle(t.bull)
                            Spacer()
                            Text(String(format: "SELL %.0f%%", 100.0 - buyPct)).foregroundStyle(t.bear)
                        }
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))

                        GeometryReader { g in
                            HStack(spacing: 1) {
                                Rectangle().fill(t.bull).frame(width: g.size.width * CGFloat(buyPct / 100.0))
                                Rectangle().fill(t.bear)
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 7)

                        if store.orderFlowTrades.isEmpty {
                            Text(store.instrument.binanceSymbol == nil && store.dataMode == .live
                                 ? "Live trade tape streams on PAXG/USDT (Gold 24/7), BTC/USD & ETH/USD."
                                 : "Waiting for incoming trades...")
                                .font(.system(size: 11.5))
                                .foregroundStyle(t.secondaryText)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(store.orderFlowTrades.prefix(10)) { tr in
                                    HStack {
                                        Text(tr.isBuyerAggressor ? "▲" : "▼")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(tr.isBuyerAggressor ? t.bull : t.bear)
                                        Text(store.instrument.formatPrice(tr.price))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(tr.isBuyerAggressor ? t.bull : t.bear)
                                        Spacer()
                                        Text(formatUSD(tr.usdValue))
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundStyle(tr.usdValue >= 10_000 ? t.amber : t.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. Active Price Alerts
                panelCard(title: "PRICE ALERTS (\(store.alerts.count))", theme: t) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            store.alertStudyKind = .concept
                        } label: {
                            Label("New Alert at Current Level", systemImage: "bell.badge.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(t.accent)
                        }
                        .buttonStyle(.plain)

                        ForEach(store.alerts.prefix(6)) { al in
                            HStack(spacing: 6) {
                                Image(systemName: al.isTriggered ? "checkmark.circle.fill" : "bell")
                                    .font(.system(size: 11))
                                    .foregroundStyle(al.isTriggered ? t.bull : t.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(al.instrument) \(al.isAbove ? ">" : "<") \(String(format: "%.2f", al.targetPrice))")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(t.primaryText)
                                    Text(al.note)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(t.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    store.removeAlert(id: al.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(t.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // 4. Saved Drawings
                panelCard(title: "SAVED DRAWINGS (\(store.currentDrawings.count))", theme: t) {
                    if store.currentDrawings.isEmpty {
                        Text("Pick a drawing tool on the left rail and click/drag on the chart. Auto-saved.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(t.secondaryText)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(store.currentDrawings) { d in
                                HStack(spacing: 6) {
                                    Circle().fill(d.color).frame(width: 8, height: 8)
                                    Text(d.tool.rawValue)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(t.primaryText)
                                    Spacer()
                                    Text(store.instrument.formatPrice(d.start.price))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(t.secondaryText)
                                    Button {
                                        store.removeDrawing(id: d.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(t.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: store.tradeDrawerWidth)
        .background(t.canvasBg)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }

    private func orderActionButton(isBuy: Bool, color: Color) -> some View {
        let side = isBuy ? "BUY" : "SELL"
        let title = orderMode == .market ? side : "\(side) \(orderMode.rawValue.uppercased())"
        let marketPx = isBuy ? (store.lastPrice + store.instrument.spread * 0.5) : (store.lastPrice - store.instrument.spread * 0.5)
        let entryPx = orderMode == .market ? marketPx : (pendingEntryPrice > 0 ? pendingEntryPrice : store.lastPrice)
        return Button {
            switch orderMode {
            case .market: store.openSampleOrder(isBuy: isBuy)
            case .limit:  store.placePendingOrder(kind: .limit, isBuy: isBuy, entryPrice: entryPx)
            case .stop:   store.placePendingOrder(kind: .stop, isBuy: isBuy, entryPrice: entryPx)
            }
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 10.5, weight: .black))
                Text(store.instrument.formatPrice(entryPx))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(color, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func formatUSD(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "$%.1fK", value / 1_000) }
        return String(format: "$%.0f", value)
    }

    private func panelCard<Content: View>(title: String, theme t: AppTheme, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(t.secondaryText)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))
    }

    private func numberField(_ label: String, value: Binding<Double>, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.secondaryText)
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(t.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(t.softSurface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(t.border, lineWidth: 0.8))
        }
    }
}
