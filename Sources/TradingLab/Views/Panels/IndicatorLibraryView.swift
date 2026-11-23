import SwiftUI

/// Clean card-based Indicator Library modal inspired by modern study-card design:
/// Top featured Strategy Setups toggle + 6 bundled study cards with Add / ✓ / Hide / Alert / Settings / Remove.
struct IndicatorLibraryView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = store.theme
        VStack(spacing: 0) {
            // Sheet Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Indicators & Studies")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(t.primaryText)
                    Text("Add clean bundled indicator suites to your chart or fine-tune any study.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.secondaryText)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        for k in StudyKind.allCases { store.addStudy(k) }
                    }
                } label: {
                    Text("Show All 6")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(t.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(t.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(t.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(t.softSurface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(t.cardBg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(t.border).frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 12) {
                    // Featured Strategy Setups Toggle Card
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Strategy Setups Overlay")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(t.primaryText)
                            Text("Show causal chart entry setups & R-multiple outcomes. Bot status stays unchanged.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(t.secondaryText)
                        }
                        Spacer()
                        Toggle("", isOn: $store.showBacktestSignalsOnChart)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(t.softSurface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(t.border, lineWidth: 1))

                    // 6 Bundled Indicator Study Cards
                    ForEach(StudyKind.allCases) { kind in
                        studyCard(kind: kind, theme: t)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 640)
        .background(t.canvasBg)
    }

    @ViewBuilder
    private func studyCard(kind: StudyKind, theme t: AppTheme) -> some View {
        let added = store.isStudyAdded(kind)
        let visible = store.isStudyVisible(kind)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                // Candlestick icon + Title & Description
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(t.accent)
                        Text(kind.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(t.primaryText)
                    }
                    Text(kind.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if added {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(t.primaryText)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            store.addStudy(kind)
                        }
                    } label: {
                        Text("Add")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(t.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(t.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Action row when study is on the chart
            if added {
                HStack(spacing: 20) {
                    actionButton(
                        icon: visible ? "eye" : "eye.slash",
                        label: visible ? "Hide" : "Show",
                        color: t.accent
                    ) {
                        store.toggleStudyVisibility(kind)
                    }

                    actionButton(
                        icon: "bell.badge",
                        label: "Create alert",
                        color: t.accent
                    ) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            store.alertStudyKind = kind
                        }
                    }

                    actionButton(
                        icon: "gearshape",
                        label: "Settings",
                        color: t.accent
                    ) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            store.settingsStudyKind = kind
                        }
                    }

                    actionButton(
                        icon: "xmark",
                        label: "Remove",
                        color: t.accent
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            store.removeStudy(kind)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(t.cardBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(added ? t.accent.opacity(0.32) : t.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(t.isDark ? 0.18 : 0.03), radius: 6, y: 2)
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .medium))
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// Clean per-study settings modal opened when clicking "Settings" on any study card or on-chart legend.
struct StudySettingsSheet: View {
    @EnvironmentObject var store: WorkspaceStore
    let kind: StudyKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = store.theme
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(t.accent)
                    Text("\(kind.title) Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(t.primaryText)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(18)
            .background(t.cardBg)
            .overlay(alignment: .bottom) { Rectangle().fill(t.border).frame(height: 1) }

            Form {
                switch kind {
                case .concept:
                    Section("Market Structure & Order Blocks") {
                        Toggle("Show BOS / CHoCH / CHoCH+ Breaks", isOn: $store.indicatorConfig.conceptShowStructure)
                        Toggle("Show Order Blocks + Pressure %", isOn: $store.indicatorConfig.conceptShowOrderBlocks)
                        Toggle("Show RSI Regular Divergences", isOn: $store.indicatorConfig.conceptShowDivergences)
                        Stepper("Internal Swing Lookback: \(store.indicatorConfig.conceptSwingLookback)", value: $store.indicatorConfig.conceptSwingLookback, in: 2...12)
                        Stepper("Macro Swing Lookback: \(store.indicatorConfig.conceptMacroSwingLookback)", value: $store.indicatorConfig.conceptMacroSwingLookback, in: 10...50, step: 5)
                        Stepper("Active OBs Per Side: \(store.indicatorConfig.conceptOrderCount)", value: $store.indicatorConfig.conceptOrderCount, in: 1...6)
                    }
                    Section("Moving Averages & Volume Profile") {
                        Toggle("EMA 20", isOn: $store.indicatorConfig.conceptShowEMA20)
                        Toggle("EMA 50", isOn: $store.indicatorConfig.conceptShowEMA50)
                        Toggle("EMA 200", isOn: $store.indicatorConfig.conceptShowEMA200)
                        Toggle("Visible-Range Volume Profile + POC", isOn: $store.indicatorConfig.conceptShowVolumeProfile)
                        Stepper("Profile Bins: \(store.indicatorConfig.conceptProfileBins)", value: $store.indicatorConfig.conceptProfileBins, in: 16...64, step: 4)
                    }

                case .orderFlow:
                    Section("Accelerators (BuAx / BeAx)") {
                        Toggle("Show Accelerator Markers (BuAx/BeAx)", isOn: $store.indicatorConfig.orderFlowShowImpulse)
                        Toggle("High-Conviction Plus Only (BuAx+/BeAx+)", isOn: $store.indicatorConfig.orderFlowPlusOnly)
                        Toggle("Highlight Wickless Stars (★)", isOn: $store.indicatorConfig.orderFlowShowWicklessStars)
                        HStack {
                            Text("Range Factor: \(String(format: "%.1fx", store.indicatorConfig.orderFlowRangeFactor))")
                            Slider(value: $store.indicatorConfig.orderFlowRangeFactor, in: 1.1...2.5, step: 0.1)
                        }
                        HStack {
                            Text("Delta Surge Factor: \(String(format: "%.1fx", store.indicatorConfig.orderFlowDeltaFactor))")
                            Slider(value: $store.indicatorConfig.orderFlowDeltaFactor, in: 1.1...2.5, step: 0.1)
                        }
                    }
                    Section("Levels, Gaps & Volume Zones") {
                        Toggle("Show Protected Swing Levels", isOn: $store.indicatorConfig.orderFlowShowProtectedLevels)
                        Toggle("Show High-Volume Zones (2.0x+)", isOn: $store.indicatorConfig.orderFlowShowVolumeZones)
                        Toggle("Show Fair Value Gaps (FVG)", isOn: $store.indicatorConfig.orderFlowShowFVG)
                        Toggle("Show Bottom Volume Histogram", isOn: $store.indicatorConfig.orderFlowShowVolumeHistogram)
                    }

                case .reversalTargets:
                    Section("Volatility Envelope & BB/RSI Reversals") {
                        Toggle("Show Volatility Band (13 × 2.718)", isOn: $store.indicatorConfig.revShowVolatilityBand)
                        Toggle("Show Bollinger Bands (20, 2.0)", isOn: $store.indicatorConfig.revShowBollinger)
                        Stepper("BB Length: \(store.indicatorConfig.revBBLength)", value: $store.indicatorConfig.revBBLength, in: 10...50)
                        HStack {
                            Text("BB Multiplier: \(String(format: "%.1f", store.indicatorConfig.revBBMultiplier))")
                            Slider(value: $store.indicatorConfig.revBBMultiplier, in: 1.0...3.5, step: 0.1)
                        }
                        HStack {
                            Text("RSI Lower: \(Int(store.indicatorConfig.revRSILower))")
                            Slider(value: $store.indicatorConfig.revRSILower, in: 15...40, step: 1)
                        }
                        HStack {
                            Text("RSI Upper: \(Int(store.indicatorConfig.revRSIUpper))")
                            Slider(value: $store.indicatorConfig.revRSIUpper, in: 60...85, step: 1)
                        }
                    }
                    Section("ATR Stop & 3 Take Profits") {
                        HStack {
                            Text("ATR Stop Multiplier: \(String(format: "%.1fx", store.indicatorConfig.revATRStopMult))")
                            Slider(value: $store.indicatorConfig.revATRStopMult, in: 0.8...3.5, step: 0.1)
                        }
                        Toggle("Show Previous Daily High / Low", isOn: $store.indicatorConfig.revShowPrevHighLow)
                    }

                case .sessionToolkits:
                    Section("Pivots & Session Profile") {
                        Toggle("Show Pivot Levels (P2–P5)", isOn: $store.indicatorConfig.toolkitShowPivots)
                        Picker("Pivot Formula", selection: $store.indicatorConfig.toolkitPivotKind) {
                            ForEach(PivotKind.allCases) { p in Text(p.rawValue).tag(p) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("Value Area %: \(Int(store.indicatorConfig.toolkitValueAreaPercent))%")
                            Slider(value: $store.indicatorConfig.toolkitValueAreaPercent, in: 50...90, step: 5)
                        }
                        Toggle("Show 5-Day ADR & Killzone Card", isOn: $store.indicatorConfig.toolkitShowADR)
                    }

                case .sidewayDetector:
                    Section("Scalp Zones (Impulse → Quiet → OB)") {
                        Toggle("Show Scalp Zones on Chart", isOn: $store.indicatorConfig.sidewayShowScalpZones)
                        HStack {
                            Text("Big Move Threshold: \(String(format: "%.1fx", store.indicatorConfig.sidewayScMove))")
                            Slider(value: $store.indicatorConfig.sidewayScMove, in: 1.3...4.0, step: 0.1)
                        }
                        Stepper("Quiet Candles Needed: \(store.indicatorConfig.sidewayScQuietBars)", value: $store.indicatorConfig.sidewayScQuietBars, in: 2...12)
                        HStack {
                            Text("OB Pressure Share ≥ \(Int(store.indicatorConfig.sidewayScSharePct))%")
                            Slider(value: $store.indicatorConfig.sidewayScSharePct, in: 50...85, step: 5)
                        }
                    }
                    Section("ADX Cycle & UTC+7 Working Hours") {
                        Stepper("ADX Length: \(store.indicatorConfig.sidewayADXLength)", value: $store.indicatorConfig.sidewayADXLength, in: 5...30)
                        HStack {
                            Text("Peak Threshold: \(Int(store.indicatorConfig.sidewayADXPeak))")
                            Slider(value: $store.indicatorConfig.sidewayADXPeak, in: 30...70, step: 1)
                        }
                        HStack {
                            Text("Flat / Compression: \(Int(store.indicatorConfig.sidewayADXFlat))")
                            Slider(value: $store.indicatorConfig.sidewayADXFlat, in: 12...40, step: 1)
                        }
                        HStack {
                            Text("ADR Gate Opens At: \(Int(store.indicatorConfig.sidewayADRGatePct))%")
                            Slider(value: $store.indicatorConfig.sidewayADRGatePct, in: 20...90, step: 5)
                        }
                        Stepper("Start Hour (UTC+7): \(store.indicatorConfig.sidewayWorkStartHour):00", value: $store.indicatorConfig.sidewayWorkStartHour, in: 0...23)
                        Stepper("End Hour (UTC+7): \(store.indicatorConfig.sidewayWorkEndHour):00", value: $store.indicatorConfig.sidewayWorkEndHour, in: 0...23)
                    }

                case .momentumOscillator:
                    Section("WaveTrend, ZVWAP & HA Bias") {
                        Picker("Mode", selection: $store.indicatorConfig.oscillatorMode) {
                            ForEach(OscillatorKind.allCases) { k in Text(k.rawValue).tag(k) }
                        }
                        .pickerStyle(.segmented)
                        if store.indicatorConfig.oscillatorMode == .waveTrend {
                            Toggle("Smart Reversals Only (±OB/OS)", isOn: $store.indicatorConfig.oscSmartOnly)
                            Toggle("Show Regular Divergences", isOn: $store.indicatorConfig.oscShowDivergences)
                            Toggle("Show ZVWAP Curve (20)", isOn: $store.indicatorConfig.oscShowZVWAP)
                            Toggle("Show Heikin-Ashi Trend Ribbon", isOn: $store.indicatorConfig.oscShowHABias)
                            Stepper("Channel Length: \(store.indicatorConfig.wtChannelLength)", value: $store.indicatorConfig.wtChannelLength, in: 4...30)
                            Stepper("Average Length: \(store.indicatorConfig.wtAverageLength)", value: $store.indicatorConfig.wtAverageLength, in: 8...50)
                            HStack {
                                Text("Overbought / Oversold: ±\(Int(store.indicatorConfig.wtOverbought))")
                                Slider(
                                    value: Binding(
                                        get: { store.indicatorConfig.wtOverbought },
                                        set: {
                                            store.indicatorConfig.wtOverbought = $0
                                            store.indicatorConfig.wtOversold = -$0
                                        }
                                    ),
                                    in: 35...75,
                                    step: 1
                                )
                            }
                        } else {
                            Stepper("RSI Length: \(store.indicatorConfig.rsiLength)", value: $store.indicatorConfig.rsiLength, in: 5...30)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 455, height: 500)
        .background(t.canvasBg)
    }
}

/// Clean alert creation modal triggered from "Create alert" on any indicator card.
struct CreateAlertSheet: View {
    @EnvironmentObject var store: WorkspaceStore
    let studyTitle: String
    @Environment(\.dismiss) private var dismiss

    @State private var isAbove: Bool = true
    @State private var targetPrice: Double = 0
    @State private var note: String = ""

    var body: some View {
        let t = store.theme
        VStack(spacing: 0) {
            HStack {
                Label("Create Price Alert", systemImage: "bell.badge.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(t.primaryText)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(t.secondaryText)
            }
            .padding(18)
            .background(t.cardBg)
            .overlay(alignment: .bottom) { Rectangle().fill(t.border).frame(height: 1) }

            Form {
                Section("Trigger Condition") {
                    LabeledContent("Instrument", value: store.instrument.rawValue)
                    LabeledContent("Study Context", value: studyTitle)
                    Picker("Condition", selection: $isAbove) {
                        Text("Price Crosses Above").tag(true)
                        Text("Price Crosses Below").tag(false)
                    }
                    TextField("Target Price", value: $targetPrice, format: .number)
                    TextField("Note (e.g., OB retest confirmation)", text: $note)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Create Alert") {
                    store.addAlert(
                        studyTitle: studyTitle,
                        isAbove: isAbove,
                        targetPrice: targetPrice,
                        note: note.isEmpty ? "\(studyTitle) level hit" : note
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(t.cardBg)
        }
        .frame(width: 400, height: 320)
        .onAppear {
            targetPrice = store.lastPrice + (store.instrument.pipSize * 15.0)
        }
    }
}
