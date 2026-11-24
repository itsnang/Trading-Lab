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
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance Journal")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Auto-saved locally — review closed Paper Desk trades or log live executions to measure your setup edge.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                }

                // Unified Hairline-Divided Metric Strip
                HStack(spacing: 0) {
                    statCell("TRADES", "\(entries.count)", t.primaryText, theme: t)
                    Rectangle().fill(t.border).frame(width: 1)
                    statCell("WIN RATE", String(format: "%.1f%%", winRate), winRate >= 50 ? t.bull : t.amber, theme: t)
                    Rectangle().fill(t.border).frame(width: 1)
                    statCell("NET PNL", String(format: "%@$%.2f", totalPnL >= 0 ? "+" : "-", abs(totalPnL)), totalPnL >= 0 ? t.bull : t.bear, theme: t)
                    Rectangle().fill(t.border).frame(width: 1)
                    statCell("AVG R", String(format: "%+.2fR", avgR), avgR >= 0 ? t.accent : t.bear, theme: t)
                    Rectangle().fill(t.border).frame(width: 1)
                    statCell("DISCIPLINE", String(format: "%.0f%%", disciplinePct), disciplinePct >= 80 ? t.bull : t.amber, theme: t)
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusPanel))
                .overlay(RoundedRectangle(cornerRadius: t.radiusPanel).stroke(t.border, lineWidth: 1))

                if !entries.isEmpty {
                    let bySetup = Dictionary(grouping: entries, by: \.setupTag)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(bySetup.keys.sorted(), id: \.self) { tag in
                                let group = bySetup[tag] ?? []
                                let wr = (Double(group.filter { $0.pnlUSD > 0 }.count) / Double(max(1, group.count))) * 100.0
                                HStack(spacing: 6) {
                                    Text(tag).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(t.primaryText)
                                    Text(String(format: "%.0f%% (%d)", wr, group.count))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(wr >= 50 ? t.bull : t.amber)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusSharp))
                                .overlay(RoundedRectangle(cornerRadius: t.radiusSharp).stroke(t.border, lineWidth: 0.75))
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    if entries.isEmpty {
                        Text("No trades logged yet. Log a trade on the right, or close a position from Paper Desk to auto-log it here.")
                            .font(.system(size: 12))
                            .foregroundStyle(t.secondaryText)
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(entries) { e in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 7) {
                                                Text(e.isBuy ? "BUY" : "SELL")
                                                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2.5)
                                                    .background((e.isBuy ? t.bull : t.bear).opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                                                    .foregroundStyle(e.isBuy ? t.bull : t.bear)

                                                Text("\(e.instrument) · \(e.timeframe)")
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(t.primaryText)
                                                Text(e.setupTag)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(t.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                                    .foregroundStyle(t.accent)
                                                Text(e.disciplineTag)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(t.softSurface, in: RoundedRectangle(cornerRadius: 3))
                                                    .foregroundStyle(t.secondaryText)
                                                if e.isLiveAccount {
                                                    Text("LIVE")
                                                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(t.bull.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                                                        .foregroundStyle(t.bull)
                                                }
                                            }
                                            if !e.notes.isEmpty {
                                                Text(e.notes)
                                                    .font(.system(size: 11.5))
                                                    .foregroundStyle(t.secondaryText)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(String(format: "%@$%.2f", e.pnlUSD >= 0 ? "+" : "-", abs(e.pnlUSD)))
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundStyle(e.pnlUSD >= 0 ? t.bull : t.bear)
                                            Text(String(format: "%+.2fR · %.2f lots", e.rMultiple, e.lots))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(t.secondaryText)
                                        }
                                        Button {
                                            store.deleteJournalEntry(id: e.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(t.secondaryText)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .overlay(alignment: .bottom) { Rectangle().fill(t.border.opacity(0.55)).frame(height: 0.5) }
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
            .frame(maxWidth: .infinity)

            // Docked Right Entry Form
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LOG NEW TRADE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(t.accent)

                    Text("\(store.instrument.rawValue) · \(store.timeframe.rawValue)")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.primaryText)

                    HStack(spacing: 2) {
                        Button { isBuy = true } label: {
                            Text("LONG")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(isBuy ? t.bull : Color.clear, in: RoundedRectangle(cornerRadius: t.radiusSharp))
                                .foregroundStyle(isBuy ? .white : t.secondaryText)
                        }.buttonStyle(.plain)
                        Button { isBuy = false } label: {
                            Text("SHORT")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(!isBuy ? t.bear : Color.clear, in: RoundedRectangle(cornerRadius: t.radiusSharp))
                                .foregroundStyle(!isBuy ? .white : t.secondaryText)
                        }.buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(t.softSurface, in: RoundedRectangle(cornerRadius: t.radiusControl))

                    Toggle("Live Broker Trade", isOn: $isLiveBrokerTrade)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11.5, weight: .medium))

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PNL ($)").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                            TextField("", value: $pnlUSD, format: .number).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("R-MULTIPLE").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                            TextField("", value: $rMultiple, format: .number).textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ENTRY PRICE").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                            TextField(store.instrument.formatPrice(store.lastPrice), text: $entryPriceText).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("EXIT PRICE").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                            TextField(store.instrument.formatPrice(store.lastPrice), text: $exitPriceText).textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SETUP PATTERN").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                        Picker("", selection: $setupTag) {
                            ForEach(JournalEntry.setupTags, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("EXECUTION DISCIPLINE").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                        Picker("", selection: $disciplineTag) {
                            ForEach(JournalEntry.disciplineTags, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NOTES").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                        TextEditor(text: $notes)
                            .font(.system(size: 11.5))
                            .frame(height: 82)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(t.cardBg, in: RoundedRectangle(cornerRadius: t.radiusControl))
                            .overlay(RoundedRectangle(cornerRadius: t.radiusControl).stroke(t.border, lineWidth: 0.75))
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
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8.5)
                            .background(t.accent, in: RoundedRectangle(cornerRadius: t.radiusControl))
                            .foregroundStyle(t.isDark ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .frame(width: 300)
            .background(t.chromeBg)
            .overlay(alignment: .leading) {
                Rectangle().fill(t.border).frame(width: 1)
            }
        }
        .background(t.canvasBg)
    }

    private func statCell(_ title: String, _ val: String, _ tint: Color, theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(t.secondaryText)
            Text(val)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
