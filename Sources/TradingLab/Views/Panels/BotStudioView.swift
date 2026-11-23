import SwiftUI
import AppKit

struct BotStudioView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var selectedTab = 0
    @State private var copiedNotice = false

    var body: some View {
        let t = store.theme

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Automation & Strategy Studio")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Configure local bot templates, basket protection, adaptive grid spacing, and 4-stage rule ASTs.")
                        .font(.system(size: 12))
                        .foregroundStyle(t.secondaryText)
                }
                Spacer()

                Picker("", selection: $selectedTab) {
                    Text("Basket Manager").tag(0)
                    Text("Adaptive Grid").tag(1)
                    Text("4-Stage Rules").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 340)

                Button {
                    copyCurrentJSON()
                } label: {
                    Label(copiedNotice ? "Copied JSON" : "Copy JSON", systemImage: copiedNotice ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(t.cardBg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(t.border).frame(height: 1)
            }

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedTab == 0 { basketEditor(t) }
                        else if selectedTab == 1 { adaptiveGridEditor(t) }
                        else { fourStageEditor(t) }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE CONFIG JSON")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.secondaryText)
                    ScrollView {
                        Text(encodedCurrentJSON())
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(t.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .frame(width: 360)
                .background(t.cardBg)
                .overlay(alignment: .leading) {
                    Rectangle().fill(t.border).frame(width: 1)
                }
            }
        }
        .background(t.canvasBg)
    }

    private func basketEditor(_ t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionBox("BASKET PROTECTION", theme: t) {
                Toggle("Enable Basket Take Profit", isOn: $store.basketConfig.enableBasketTP)
                HStack {
                    Text("TP Value (%)").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.basketConfig.tpValue, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                Toggle("Auto Close At TP", isOn: $store.basketConfig.autoCloseAtTP)
                Divider().overlay(t.border)
                Toggle("Enable Basket Stop Loss", isOn: $store.basketConfig.enableBasketSL)
                HStack {
                    Text("SL Value (%)").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.basketConfig.slValue, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                Toggle("Auto Close At SL", isOn: $store.basketConfig.autoCloseAtSL)
            }

            sectionBox("OPTIONAL GRID LAYERING", theme: t) {
                Toggle("Enable Grid Entries", isOn: $store.basketConfig.enableGridEntries)
                HStack {
                    Text("Grid Step (pips)").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.basketConfig.gridStepPips, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Lot Multiplier").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.basketConfig.gridLotMultiplier, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                Stepper("Max Grid Levels: \(store.basketConfig.gridMaxLevels)", value: $store.basketConfig.gridMaxLevels, in: 1...20)
                Toggle("Manage Manual Trades", isOn: $store.basketConfig.manageManualTrades)
            }
        }
    }

    private func adaptiveGridEditor(_ t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionBox("LOT & ADAPTIVE STEP", theme: t) {
                HStack {
                    Text("Starting Lots").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.adaptiveGridConfig.startingLots, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Layer Multiplier").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.adaptiveGridConfig.layerMultiplier, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                Picker("Offset Algorithm", selection: $store.adaptiveGridConfig.pipStepMode) {
                    Text("0 · Fixed Pip Step").tag(0)
                    Text("1 · ATR Simple").tag(1)
                    Text("2 · ATR Percentile").tag(2)
                    Text("3 · Bollinger Width").tag(3)
                    Text("4 · Price Range").tag(4)
                    Text("5 · Hybrid Volatility").tag(5)
                }
                HStack {
                    Text("Base Pip Step").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.adaptiveGridConfig.pipStep, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
            }

            sectionBox("SESSION FILTER (UTC+7)", theme: t) {
                Toggle("Enable Session Filter", isOn: $store.adaptiveGridConfig.enableSessionFilter)
                Toggle("Close All Outside Session", isOn: $store.adaptiveGridConfig.closeAllOutsideSession)
                Toggle("Asia Session (\(store.adaptiveGridConfig.asiaSession))", isOn: $store.adaptiveGridConfig.tradeAsia)
                Toggle("London Session (\(store.adaptiveGridConfig.londonSession))", isOn: $store.adaptiveGridConfig.tradeLondon)
                Toggle("New York Session (\(store.adaptiveGridConfig.newYorkSession))", isOn: $store.adaptiveGridConfig.tradeNewYork)
            }

            sectionBox("SAFETY & SIGNAL GATE", theme: t) {
                Toggle("Stochastic Entry Gate (\(Int(store.adaptiveGridConfig.stochLower)) / \(Int(store.adaptiveGridConfig.stochUpper)))", isOn: $store.adaptiveGridConfig.stochasticGateActive)
                Toggle("Enable Equity Drawdown Stop (\(Int(store.adaptiveGridConfig.stopLossDrawdownPct))%)", isOn: $store.adaptiveGridConfig.enableEquityProtection)
                Toggle("Enable Spread Filter (Max \(Int(store.adaptiveGridConfig.maxSpreadPips)) pips)", isOn: $store.adaptiveGridConfig.enableSpreadFilter)
            }
        }
    }

    private func fourStageEditor(_ t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionBox("RISK & EXECUTION", theme: t) {
                HStack {
                    Text("Preset Name").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", text: $store.strategyConfig.presetName).frame(width: 220).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Target R:R").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.strategyConfig.riskReward, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Near Block Tolerance (× ATR)").foregroundStyle(t.secondaryText)
                    Spacer()
                    TextField("", value: $store.strategyConfig.nearATR, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                }
                Toggle("Enable Partial Take Profit", isOn: $store.strategyConfig.partialTakeProfit)
            }

            stageList("1 · TREND STAGE", rules: $store.strategyConfig.trendRules, theme: t)
            stageList("2 · SETUP STAGE", rules: $store.strategyConfig.setupRules, theme: t)
            stageList("3 · RETEST STAGE", rules: $store.strategyConfig.retestRules, theme: t)
            stageList("4 · ENTRY STAGE", rules: $store.strategyConfig.entryRules, theme: t)
        }
    }

    private func stageList(_ title: String, rules: Binding<[RuleCondition]>, theme t: AppTheme) -> some View {
        sectionBox(title, theme: t) {
            ForEach(rules) { $rule in
                HStack(spacing: 8) {
                    Text(rule.kind).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(t.accent).frame(width: 120, alignment: .leading)
                    Text(rule.compare).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(t.amber)
                    TextField("", value: $rule.value, format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                    Spacer()
                    Text("lookback \(rule.lookback)").font(.system(size: 11, design: .monospaced)).foregroundStyle(t.secondaryText)
                }
            }
        }
    }

    private func sectionBox<Content: View>(_ title: String, theme t: AppTheme, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(t.secondaryText)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.border, lineWidth: 1))
    }

    private func encodedCurrentJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data?
        if selectedTab == 0 { data = try? enc.encode(store.basketConfig) }
        else if selectedTab == 1 { data = try? enc.encode(store.adaptiveGridConfig) }
        else { data = try? enc.encode(store.strategyConfig) }
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func copyCurrentJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(encodedCurrentJSON(), forType: .string)
        copiedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copiedNotice = false }
    }
}
