import SwiftUI

struct JournalView: View {
    @EnvironmentObject var store: WorkspaceStore

    @State private var isBuy = true
    @State private var entryPriceText = ""
    @State private var exitPriceText = ""
    @State private var lots: Double = 0.10
    @State private var pnlUSD: Double = 120.0
    @State private var rMultiple: Double = 1.5
    @State private var setupTag = JournalEntry.setupTags[0]
    @State private var disciplineTag = JournalEntry.disciplineTags[0]
    @State private var notes = ""
    @State private var isLiveBrokerTrade = true

    var body: some View {
        let t = store.theme
        let entries = store.journalEntries
        let wins = entries.filter { $0.pnlUSD > 0 }
        let winRate = entries.isEmpty ? 0 : (Double(wins.count) / Double(entries.count)) * 100.0
        let totalPnL = entries.reduce(0.0) { $0 + $1.pnlUSD }
        let avgR = entries.isEmpty ? 0 : (entries.reduce(0.0) { $0 + $1.rMultiple } / Double(entries.count))
        let disciplinedCount = entries.filter { $0.disciplineTag == "Followed Plan" || $0.disciplineTag == "Calm & Patient" }.count
        let disciplinePct = entries.isEmpty ? 100.0 : (Double(disciplinedCount) / Double(entries.count)) * 100.0

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Day-Trading Performance Journal")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Auto-saved locally — log real broker trades or review closed paper trades to spot your highest-edge setups.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                }

                HStack(spacing: 12) {
                    statBox("LOGGED TRADES", "\(entries.count)", t.primaryText, theme: t)
                    statBox("WIN RATE", String(format: "%.1f%%", winRate), winRate >= 50 ? t.bull : t.amber, theme: t)
                    statBox("NET PNL", String(format: "%@$%.2f", totalPnL >= 0 ? "+" : "-", abs(totalPnL)), totalPnL >= 0 ? t.bull : t.bear, theme: t)
                    statBox("AVG R", String(format: "%+.2fR", avgR), avgR >= 0 ? t.accent : t.bear, theme: t)
                    statBox("DISCIPLINE", String(format: "%.0f%%", disciplinePct), disciplinePct >= 80 ? t.bull : t.amber, theme: t)
                }

                if !entries.isEmpty {
                    let bySetup = Dictionary(grouping: entries, by: \.setupTag)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(bySetup.keys.sorted(), id: \.self) { tag in
                                let group = bySetup[tag] ?? []
                                let wr = (Double(group.filter { $0.pnlUSD > 0 }.count) / Double(max(1, group.count))) * 100.0
                                HStack(spacing: 6) {
                                    Text(tag).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.primaryText)
                                    Text(String(format: "%.0f%% (%d)", wr, group.count))
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(wr >= 50 ? t.bull : t.amber)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(t.cardBg, in: Capsule())
                                .overlay(Capsule().stroke(t.border, lineWidth: 0.9))
                            }
                        }
                    }
                }

                ScrollView {
                    if entries.isEmpty {
                        Text("No trades logged yet. Log a real trade on the right, or close a position from the Terminal to auto-log it here.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(t.secondaryText)
                            .padding(.top, 30)
                    } else {
                        VStack(spacing: 9) {
                            ForEach(entries) { e in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(e.isBuy ? "BUY" : "SELL")
                                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2.5)
                                                .background((e.isBuy ? t.bull : t.bear).opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                                                .foregroundStyle(e.isBuy ? t.bull : t.bear)

                                            Text("\(e.instrument) · \(e.timeframe)")
                                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                                .foregroundStyle(t.primaryText)
                                            Text(e.setupTag)
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2.5)
                                                .background(t.accent.opacity(0.12), in: Capsule())
                                                .foregroundStyle(t.accent)
                                            Text(e.disciplineTag)
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2.5)
                                                .background(t.softSurface, in: Capsule())
                                                .foregroundStyle(t.secondaryText)
                                            if e.isLiveAccount {
                                                Text("REAL")
                                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(t.bull.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                                                    .foregroundStyle(t.bull)
                                            }
                                        }
                                        if !e.notes.isEmpty {
                                            Text(e.notes)
                                                .font(.system(size: 12))
                                                .foregroundStyle(t.secondaryText)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(String(format: "%@$%.2f", e.pnlUSD >= 0 ? "+" : "-", abs(e.pnlUSD)))
                                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(e.pnlUSD >= 0 ? t.bull : t.bear)
                                        Text(String(format: "%+.2fR · %.2f lots", e.rMultiple, e.lots))
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(t.secondaryText)
                                    }
                                    Button {
                                        store.deleteJournalEntry(id: e.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(t.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(14)
                                .background(t.cardBg, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(t.border, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("LOG NEW TRADE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.accent)

                    Text("Active: \(store.instrument.rawValue) (\(store.timeframe.rawValue))")
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(t.primaryText)

                    Picker("Direction", selection: $isBuy) {
                        Text("BUY / LONG").tag(true)
                        Text("SELL / SHORT").tag(false)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Real Broker Trade", isOn: $isLiveBrokerTrade)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PnL ($)").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                            TextField("", value: $pnlUSD, format: .number).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("R-Multiple").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                            TextField("", value: $rMultiple, format: .number).textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Entry Price").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                            TextField(store.instrument.formatPrice(store.lastPrice), text: $entryPriceText).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Exit Price").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                            TextField(store.instrument.formatPrice(store.lastPrice), text: $exitPriceText).textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Setup Pattern").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                        Picker("", selection: $setupTag) {
                            ForEach(JournalEntry.setupTags, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Execution Discipline").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                        Picker("", selection: $disciplineTag) {
                            ForEach(JournalEntry.disciplineTags, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lesson / Notes").font(.system(size: 10.5)).foregroundStyle(t.secondaryText)
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .frame(height: 86)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(t.softSurface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border, lineWidth: 0.8))
                    }

                    Button {
                        let ePrice = Double(entryPriceText) ?? store.lastPrice
                        let xPrice = Double(exitPriceText) ?? store.lastPrice
                        let item = JournalEntry(
                            instrument: store.instrument.rawValue,
                            timeframe: store.timeframe.rawValue,
                            isBuy: isBuy,
                            entryPrice: ePrice,
                            exitPrice: xPrice,
                            lots: lots,
                            pnlUSD: pnlUSD,
                            rMultiple: rMultiple,
                            setupTag: setupTag,
                            disciplineTag: disciplineTag,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                            isLiveAccount: isLiveBrokerTrade
                        )
                        store.addJournalEntry(item)
                        notes = ""
                    } label: {
                        Text("Save to Journal")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(t.accent, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .frame(width: 320)
            .background(t.cardBg)
            .overlay(alignment: .leading) {
                Rectangle().fill(t.border).frame(width: 1)
            }
        }
        .background(t.canvasBg)
    }

    private func statBox(_ title: String, _ val: String, _ tint: Color, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
            Text(val).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.cardBg, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(t.border, lineWidth: 1))
    }
}
