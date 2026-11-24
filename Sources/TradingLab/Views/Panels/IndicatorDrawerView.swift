import SwiftUI

/// Docked, hairline-divided Execution Desk, Order Flow Tape & Signal Alerts panel.
private enum TicketOrderMode: String, CaseIterable, Identifiable {
    case market = "MARKET"
    case limit = "LIMIT"
    case stop = "STOP"
    var id: String { rawValue }
}

struct IndicatorDrawerView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var orderMode: TicketOrderMode = .market
    @State private var pendingEntryPrice: Double = 0

    var body: some View {
        let t = store.theme

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Paper Desk Order Ticket
                dockedSection(title: "PAPER DESK · ORDER TICKET", theme: t) {
                    VStack(spacing: 10) {
                        // Sharp custom mode tabs
                        HStack(spacing: 2) {
                            ForEach(TicketOrderMode.allCases) { mode in
                                let active = orderMode == mode
                                Button {
                                    orderMode = mode
                                    if mode != .market && pendingEntryPrice <= 0 {
                                        pendingEntryPrice = store.lastPrice
                                    }
                                } label: {
                                    Text(mode.rawValue)
                                        .font(.system(size: 10, weight: active ? .bold : .medium, design: .monospaced))
                                        .tracking(0.6)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5.5)
                                        .foregroundStyle(active ? (t.isDark ? .black : .white) : t.secondaryText)
                                        .background(
                                            active ? t.accent : Color.clear,
                                            in: RoundedRectangle(cornerRadius: t.radiusSharp)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                        .background(t.softSurface, in: RoundedRectangle(cornerRadius: t.radiusControl))

                        if orderMode != .market {
                            numberField("PENDING ENTRY PRICE", value: $pendingEntryPrice, theme: t)
                        }

                        HStack {
                            Toggle("Auto Risk Sizing", isOn: $store.autoSizeByRisk)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(t.primaryText)
                            Spacer()
                            Text(String(format: "%.2f lots", store.effectiveOrderLots))
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(t.accent)
                        }

                        HStack(spacing: 6) {
                            if store.autoSizeByRisk {
                                numberField("RISK %", value: $store.riskPercentPerTrade, theme: t)
                            } else {
                                numberField("LOTS", value: $store.orderLots, theme: t)
                            }
                            numberField("SL (PIPS)", value: $store.orderStopPips, theme: t)
                            numberField("TP (PIPS)", value: $store.orderTakeProfitPips, theme: t)
                        }

                        let rr = store.orderStopPips > 0 ? (store.orderTakeProfitPips / store.orderStopPips) : 0
                        let riskUSD = store.orderStopPips * store.effectiveOrderLots * store.instrument.dollarPerPipPerLot
                        HStack {
                            Text(String(format: "RISK $%.0f", riskUSD)).foregroundStyle(t.amber)
                            Spacer()
                            Text(String(format: "R:R 1:%.1f", rr)).foregroundStyle(rr >= 2.0 ? t.bull : t.secondaryText)
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.4)

                        HStack(spacing: 6) {
                            orderActionButton(isBuy: false, color: t.bear, theme: t)
                            orderActionButton(isBuy: true, color: t.bull, theme: t)
                        }
                    }
                }

                // 2. Live Order Flow Pressure & Tape
                dockedSection(title: "ORDER FLOW TAPE", theme: t) {
                    VStack(spacing: 8) {
                        let buyPct = store.buyPressurePercent
                        HStack {
                            Text(String(format: "BID %.0f%%", buyPct)).foregroundStyle(t.bull)
                            Spacer()
                            Text(String(format: "ASK %.0f%%", 100.0 - buyPct)).foregroundStyle(t.bear)
                        }
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)

                        GeometryReader { g in
                            HStack(spacing: 1) {
                                Rectangle().fill(t.bull).frame(width: g.size.width * CGFloat(buyPct / 100.0))
                                Rectangle().fill(t.bear)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        .frame(height: 4)

                        if store.orderFlowTrades.isEmpty {
                            Text(store.instrument.binanceSymbol == nil
                                 ? "Live trade tape streams on XAU/USD, PAXG/USDT, BTC/USD & ETH/USD."
                                 : "Waiting for incoming trades...")
                                .font(.system(size: 11))
                                .foregroundStyle(t.secondaryText)
                        } else {
                            VStack(spacing: 3) {
                                ForEach(store.orderFlowTrades.prefix(10)) { tr in
                                    HStack {
                                        Text(tr.isBuyerAggressor ? "▲" : "▼")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(tr.isBuyerAggressor ? t.bull : t.bear)
                                        Text(store.instrument.formatPrice(tr.price))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(tr.isBuyerAggressor ? t.bull : t.bear)
                                        Spacer()
                                        Text(formatUSD(tr.usdValue))
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundStyle(tr.usdValue >= 10_000 ? t.amber : t.secondaryText)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }
                }

                // 3. Auto Signal Alerts & Price Alerts
                dockedSection(title: "SIGNAL & PRICE ALERTS (\(store.alerts.count + store.recentSignalAlerts.count))", theme: t) {
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle("Confirmed Study Signals", isOn: $store.signalAlertsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(.system(size: 11, weight: .medium))
                        Toggle("Early OB / FVG Zone Touch", isOn: $store.zoneTouchAlertsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(.system(size: 11, weight: .medium))
                        HStack(spacing: 12) {
                            Toggle("macOS Banner", isOn: $store.macOSNotificationsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.system(size: 10.5, weight: .medium))
                            Toggle("Sound", isOn: $store.soundAlertsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.system(size: 10.5, weight: .medium))
                        }

                        Rectangle().fill(t.border).frame(height: 1).padding(.vertical, 2)

                        Button {
                            store.alertStudyKind = .concept
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Add Price Level Alert")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(t.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(t.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: t.radiusSharp))
                            .overlay(RoundedRectangle(cornerRadius: t.radiusSharp).stroke(t.accent.opacity(0.28), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)

                        if !store.recentSignalAlerts.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("RECENT SIGNALS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundStyle(t.secondaryText)
                                    .padding(.top, 2)
                                ForEach(store.recentSignalAlerts.prefix(4)) { ev in
                                    HStack(spacing: 6) {
                                        Rectangle()
                                            .fill(ev.category == "Zone Touch" ? t.amber : (ev.isBullish ? t.bull : t.bear))
                                            .frame(width: 2.5, height: 24)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(ev.title)
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(t.primaryText)
                                                .lineLimit(1)
                                            Text(ev.body)
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .foregroundStyle(t.secondaryText)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if ev.suggestedSL != nil && ev.suggestedTP != nil {
                                            Button("USE") {
                                                store.applySignalTargetsToOrderTicket(ev)
                                            }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(t.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(t.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }
                            }
                        }

                        ForEach(store.alerts.prefix(6)) { al in
                            HStack(spacing: 6) {
                                Image(systemName: al.isTriggered ? "checkmark.circle.fill" : "bell")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(al.isTriggered ? t.bull : t.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(al.instrument) \(al.isAbove ? ">" : "<") \(String(format: "%.2f", al.targetPrice))")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(t.primaryText)
                                    Text(al.note)
                                        .font(.system(size: 10))
                                        .foregroundStyle(t.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    store.removeAlert(id: al.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(t.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // 4. Saved Drawings
                dockedSection(title: "SAVED DRAWINGS (\(store.currentDrawings.count))", showBottomDivider: false, theme: t) {
                    if store.currentDrawings.isEmpty {
                        Text("Select a drawing tool on the left rail and drag on the chart. All levels save automatically.")
                            .font(.system(size: 11))
                            .foregroundStyle(t.secondaryText)
                    } else {
                        VStack(spacing: 5) {
                            ForEach(store.currentDrawings) { d in
                                HStack(spacing: 6) {
                                    Circle().fill(d.color).frame(width: 7, height: 7)
                                    Text(d.tool.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(t.primaryText)
                                    Spacer()
                                    Text(store.instrument.formatPrice(d.start.price))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(t.secondaryText)
                                    Button {
                                        store.removeDrawing(id: d.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(t.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: store.tradeDrawerWidth)
        .background(t.chromeBg)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }

    private func orderActionButton(isBuy: Bool, color: Color, theme t: AppTheme) -> some View {
        let side = isBuy ? "BUY" : "SELL"
        let title = orderMode == .market ? side : "\(side) \(orderMode.rawValue)"
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
                Text(title)
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .tracking(0.6)
                Text(store.instrument.formatPrice(entryPx))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color, in: RoundedRectangle(cornerRadius: t.radiusControl))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func formatUSD(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "$%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "$%.1fK", value / 1_000) }
        return String(format: "$%.0f", value)
    }

    private func dockedSection<Content: View>(
        title: String,
        showBottomDivider: Bool = true,
        theme t: AppTheme,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(t.secondaryText)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showBottomDivider {
                Rectangle().fill(t.border).frame(height: 1)
            }
        }
    }

    private func numberField(_ label: String, value: Binding<Double>, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(t.secondaryText)
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(t.primaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 5.5)
                .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusSharp))
                .overlay(RoundedRectangle(cornerRadius: t.radiusSharp).stroke(t.border, lineWidth: 0.75))
        }
    }
}
