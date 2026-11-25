import SwiftUI
import AppKit

/// Captures native macOS trackpad / mouse scroll-wheel events and TradingView keyboard shortcuts.
private struct ChartInputMonitor: NSViewRepresentable {
    let onScroll: (_ deltaX: CGFloat, _ deltaY: CGFloat, _ localPoint: CGPoint, _ viewSize: CGSize) -> Void
    let onKeyDown: (_ event: NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let v = MonitorView()
        v.onScroll = onScroll
        v.onKeyDown = onKeyDown
        return v
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onKeyDown = onKeyDown
    }

    final class MonitorView: NSView {
        var onScroll: ((_ deltaX: CGFloat, _ deltaY: CGFloat, _ localPoint: CGPoint, _ viewSize: CGSize) -> Void)?
        var onKeyDown: ((_ event: NSEvent) -> Bool)?
        private var scrollMonitor: Any?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cleanup()
            guard window != nil else { return }

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let win = self.window, event.window === win else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(loc) {
                    let flippedY = self.bounds.height - loc.y
                    self.onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, CGPoint(x: loc.x, y: flippedY), self.bounds.size)
                    return nil
                }
                return event
            }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, event.window === win else { return event }
                // Don't hijack typing inside TextFields / TextEditors
                if let responder = win.firstResponder, responder is NSTextView {
                    return event
                }
                if self.onKeyDown?(event) == true {
                    return nil
                }
                return event
            }
        }

        private func cleanup() {
            if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }

        deinit { cleanup() }
    }
}

private enum ChartDragZone {
    case none
    case plot
    case priceAxis
    case timeAxis
}

private enum DrawingEditHandle {
    case none
    case startHandle(UUID)
    case endHandle(UUID)
    case moveBody(UUID, origStart: ChartPoint, origEnd: ChartPoint)
}

struct CandlestickCanvasView: View {
    @EnvironmentObject var store: WorkspaceStore

    @State private var hoverLocation: CGPoint? = nil
    @State private var draftDrawing: DrawingObject? = nil
    @State private var isAwaitingSecondPoint: Bool = false
    @State private var hoveredDrawingId: UUID? = nil
    @State private var activeDragZone: ChartDragZone = .none
    @State private var activeEditHandle: DrawingEditHandle = .none
    @State private var lastPanTranslation: CGSize = .zero
    @State private var activeCursorZone: ChartDragZone = .none

    private let rightAxisWidth: CGFloat = 78
    private let bottomAxisHeight: CGFloat = 26
    private let topPadding: CGFloat = 14

    var body: some View {
        let t = store.theme

        GeometryReader { geo in
            let plotWidth = max(100, geo.size.width - rightAxisWidth)
            let plotHeight = max(100, geo.size.height - bottomAxisHeight - topPadding)
            let candles = store.visibleSeries
            let rangeInfo = computeVisibleRange(candles: candles, plotWidth: plotWidth)
            let hoverPrice = hoverLocation.map {
                rangeInfo.price(forY: $0.y, topPadding: topPadding, plotHeight: plotHeight)
            } ?? store.lastPrice

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawChart(
                        ctx: &ctx,
                        size: size,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight,
                        candles: candles,
                        range: rangeInfo,
                        theme: t
                    )
                }
                .background(t.chartBg)
                .background(
                    ChartInputMonitor(
                        onScroll: { dx, dy, pt, _ in
                            if pt.x > plotWidth {
                                // Smooth continuous vertical zoom over Right Price Axis
                                if abs(dy) > 0.1 {
                                    store.scalePriceAxis(deltaY: -dy * 1.4, currentMin: rangeInfo.minPrice, currentMax: rangeInfo.maxPrice)
                                }
                            } else if abs(dx) > abs(dy) * 0.9 {
                                // Smooth horizontal trackpad pan
                                let barsPerPx = store.visibleCandleCount / Double(max(plotWidth, 1.0))
                                store.pan(deltaBars: -Double(dx) * barsPerPx * 1.2)
                            } else if abs(dy) > 0.1 {
                                // Butter-smooth continuous cursor-anchored horizontal zoom
                                let anchor = max(0.04, min(0.96, Double(pt.x / max(plotWidth, 1.0))))
                                let clamped = max(-35.0, min(35.0, Double(dy)))
                                let factor = exp(-clamped * 0.009)
                                store.zoom(factor: factor, anchorFraction: anchor)
                            }
                        },
                        onKeyDown: { event in
                            handleKeyShortcut(event)
                        }
                    )
                )
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pt):
                        hoverLocation = pt
                        updateHoverCursor(pt: pt, plotWidth: plotWidth, plotHeight: plotHeight)
                        // TradingView click-move-click: smoothly move Point 2 while hovering!
                        if isAwaitingSecondPoint, var draft = draftDrawing, !draft.tool.isSinglePoint {
                            let rawEnd = chartPoint(at: pt, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: rangeInfo)
                            draft.end = applyShiftAngleSnap(start: draft.start, end: rawEnd, tool: draft.tool, plotHeight: plotHeight, range: rangeInfo)
                            draftDrawing = draft
                        } else if store.activeTool == .cursor && activeDragZone == .none {
                            let hit = hitTestDrawing(at: pt, plotWidth: plotWidth, plotHeight: plotHeight, range: rangeInfo)
                            switch hit {
                            case .startHandle(let id), .endHandle(let id), .moveBody(let id, _, _):
                                hoveredDrawingId = id
                            case .none:
                                hoveredDrawingId = nil
                            }
                        } else {
                            hoveredDrawingId = nil
                        }
                    case .ended:
                        hoverLocation = nil
                        hoveredDrawingId = nil
                        resetHoverCursor()
                    }
                }
                .onChange(of: store.activeTool) { _, newTool in
                    if newTool == .cursor {
                        draftDrawing = nil
                        isAwaitingSecondPoint = false
                    } else if draftDrawing?.tool != newTool {
                        draftDrawing = nil
                        isAwaitingSecondPoint = false
                    }
                }
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    if location.x > plotWidth {
                        store.resetPriceScale()
                    } else if location.y >= topPadding + plotHeight {
                        store.resetCamera()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value: value, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: rangeInfo)
                        }
                        .onEnded { value in
                            handleDragEnded(value: value, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: rangeInfo)
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { mag in
                            if mag > 1.02 { store.zoom(factor: 0.95, anchorFraction: 0.5) }
                            else if mag < 0.98 { store.zoom(factor: 1.05, anchorFraction: 0.5) }
                        }
                )
                .contextMenu {
                    Button("Add Alert at \(store.instrument.formatPrice(hoverPrice))") {
                        store.addAlert(
                            studyTitle: "Chart Level",
                            isAbove: hoverPrice >= store.lastPrice,
                            targetPrice: hoverPrice,
                            note: "Right-click alert"
                        )
                    }
                    Button("Add Horizontal Line at \(store.instrument.formatPrice(hoverPrice))") {
                        let idx = hoverLocation.map { rangeInfo.index(forX: $0.x) } ?? Double(candles.count - 1)
                        let pt = ChartPoint(index: idx, price: hoverPrice)
                        store.addDrawing(DrawingObject(
                            id: UUID(),
                            tool: .horizontalLine,
                            start: pt,
                            end: pt,
                            colorPresetId: store.activeColorPresetId,
                            label: "Level"
                        ))
                    }
                    Divider()
                    Button("Paper Buy \(store.instrument.rawValue) (\(String(format: "%.2f", store.effectiveOrderLots)) lots)") {
                        store.openSampleOrder(isBuy: true)
                    }
                    Button("Paper Sell \(store.instrument.rawValue) (\(String(format: "%.2f", store.effectiveOrderLots)) lots)") {
                        store.openSampleOrder(isBuy: false)
                    }
                    Divider()
                    Button("Auto Fit Price Scale") { store.resetPriceScale() }
                    Button("Reset Chart View (⌥R)") { store.resetCamera() }
                    if !store.currentDrawings.isEmpty {
                        Divider()
                        Button("Clear All Drawings (\(store.currentDrawings.count))", role: .destructive) {
                            store.clearDrawings()
                        }
                    }
                }

                // Subtle MSNR Desk Center Watermark behind chart
                VStack(spacing: 4) {
                    MSNRLogoMark(isDark: t.isDark, showSacredGrid: true)
                        .frame(width: 88, height: 88)
                    Text("\(store.instrument.rawValue) · \(store.timeframe.rawValue)")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .tracking(2.0)
                        .foregroundStyle(t.primaryText)
                }
                .opacity(t.isDark ? 0.075 : 0.055)
                .frame(width: plotWidth, height: topPadding + plotHeight)
                .allowsHitTesting(false)

                // Top-Left: OHLCV Header + Active Studies Legend
                VStack(alignment: .leading, spacing: 6) {
                    ohlcHeader(candles: candles, range: rangeInfo, plotWidth: plotWidth, theme: t)
                    activeStudiesLegend(theme: t)
                }
                .padding(12)

                // Top-Center: Floating Selected Drawing Action Bar (TradingView style!)
                if let selId = store.selectedDrawingId,
                   let selected = store.currentDrawings.first(where: { $0.id == selId }) {
                    selectedDrawingToolbar(drawing: selected, theme: t)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                // Top-Right: Active Tool Hint + Sideway Readiness Card
                VStack(alignment: .trailing, spacing: 8) {
                    if store.activeTool != .cursor {
                        activeDrawingHint(theme: t)
                    }
                    if store.isStudyVisible(.sidewayDetector) || (store.isStudyVisible(.sessionToolkits) && store.indicatorConfig.toolkitShowADR) {
                        sidewayDashboardCard(theme: t)
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, rightAxisWidth + 12)
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Bottom-Right Plot: "Jump to Latest >>" floating button when scrolled back
                if store.isScrolledBackInHistory {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            store.jumpToLatest()
                        }
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(t.primaryText)
                            .frame(width: 32, height: 32)
                            .background(t.cardBg.opacity(0.95), in: Circle())
                            .overlay(Circle().stroke(t.border, lineWidth: 1))
                            .shadow(color: .black.opacity(t.isDark ? 0.35 : 0.10), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to latest candle")
                    .position(x: plotWidth - 26, y: topPadding + plotHeight - 26)
                }

                // Bottom-Right Corner: TradingView-style "Auto" Y-scale button
                Button {
                    if store.isAutoPriceScale {
                        store.resetCamera()
                    } else {
                        store.resetPriceScale()
                    }
                } label: {
                    Text("Auto")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(store.isAutoPriceScale ? t.accent : t.secondaryText)
                        .frame(width: rightAxisWidth - 8, height: bottomAxisHeight - 6)
                        .background(
                            store.isAutoPriceScale ? t.accent.opacity(0.12) : t.softSurface,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(store.isAutoPriceScale ? t.accent.opacity(0.35) : t.border, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Auto-Fit Price Scale (or drag price axis up/down to scale vertically; double-click axis to reset)")
                .position(x: plotWidth + rightAxisWidth * 0.5, y: topPadding + plotHeight + bottomAxisHeight * 0.5)
            }
        }
    }

    // MARK: - Keyboard Shortcuts (TradingView Style)

    private func handleKeyShortcut(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Esc -> cancel in-progress drawing / exit drawing tool / deselect drawing
        if event.keyCode == 53 {
            if isAwaitingSecondPoint || draftDrawing != nil || store.activeTool != .cursor || store.selectedDrawingId != nil {
                store.activeTool = .cursor
                store.selectedDrawingId = nil
                draftDrawing = nil
                isAwaitingSecondPoint = false
                return true
            }
            return false
        }

        // Delete / Backspace -> delete selected drawing
        if (event.keyCode == 51 || event.keyCode == 117), store.selectedDrawingId != nil {
            store.deleteSelectedDrawing()
            return true
        }

        // Cmd+Z -> Undo drawing
        if mods == .command && chars == "z" {
            store.undoDrawing()
            return true
        }

        // Option shortcuts (TradingView style: Alt+T, Alt+H, Alt+F, Alt+R)
        if mods == .option {
            switch chars {
            case "t": store.activeTool = .trendLine; return true
            case "h": store.activeTool = .horizontalLine; return true
            case "f": store.activeTool = .fibRetracement; return true
            case "r": store.resetCamera(); return true
            default: break
            }
        }

        // Plain number keys 1..7 -> instant timeframe switching
        if mods.isEmpty {
            let tfs = Timeframe.allCases
            if let num = Int(chars), num >= 1, num <= tfs.count {
                store.timeframe = tfs[num - 1]
                return true
            }
        }
        return false
    }

    // MARK: - Coordinate Math & Magnet OHLC Snapping

    struct VisibleRange {
        let startIdxFloat: Double
        let endIdxFloat: Double
        let firstCandle: Int
        let lastCandle: Int
        let minPrice: Double
        let maxPrice: Double
        let candleStepX: CGFloat

        func x(forIndex idx: Double) -> CGFloat {
            CGFloat(idx - startIdxFloat) * candleStepX
        }

        func index(forX x: CGFloat) -> Double {
            startIdxFloat + Double(x / max(candleStepX, 0.1))
        }

        func y(forPrice price: Double, topPadding: CGFloat, plotHeight: CGFloat) -> CGFloat {
            let span = max(maxPrice - minPrice, 1e-6)
            let norm = (price - minPrice) / span
            return topPadding + plotHeight * CGFloat(1.0 - norm)
        }

        func price(forY y: CGFloat, topPadding: CGFloat, plotHeight: CGFloat) -> Double {
            let norm = 1.0 - Double((y - topPadding) / max(plotHeight, 1.0))
            return minPrice + norm * (maxPrice - minPrice)
        }
    }

    private func computeVisibleRange(candles: [Candle], plotWidth: CGFloat) -> VisibleRange {
        let count = max(1, candles.count)
        let vis = max(14.0, store.visibleCandleCount)
        let endIdxFloat = Double(count - 1) + store.rightOffsetBars
        let startIdxFloat = endIdxFloat - vis
        let stepX = plotWidth / CGFloat(vis)

        let first = max(0, min(count - 1, Int(floor(startIdxFloat))))
        let last = max(first, min(count - 1, Int(ceil(endIdxFloat))))

        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        if !candles.isEmpty {
            for i in first...last {
                lo = min(lo, candles[i].low)
                hi = max(hi, candles[i].high)
            }
        }
        if !lo.isFinite || !hi.isFinite || hi <= lo {
            lo = store.instrument.basePrice - store.instrument.volatility * 5
            hi = store.instrument.basePrice + store.instrument.volatility * 5
        }
        let pad = (hi - lo) * 0.11
        let finalMin: Double
        let finalMax: Double
        if store.isAutoPriceScale || store.manualPriceMax <= store.manualPriceMin {
            finalMin = lo - pad
            finalMax = hi + pad
        } else {
            finalMin = store.manualPriceMin
            finalMax = store.manualPriceMax
        }
        return VisibleRange(
            startIdxFloat: startIdxFloat,
            endIdxFloat: endIdxFloat,
            firstCandle: first,
            lastCandle: last,
            minPrice: finalMin,
            maxPrice: finalMax,
            candleStepX: stepX
        )
    }

    private func chartPoint(at screenPt: CGPoint, plotWidth: CGFloat, plotHeight: CGFloat, candles: [Candle], range: VisibleRange) -> ChartPoint {
        let rawIdx = range.index(forX: min(plotWidth, max(0, screenPt.x)))
        let rawPrice = range.price(forY: screenPt.y, topPadding: topPadding, plotHeight: plotHeight)
        guard store.magnetEnabled else {
            return ChartPoint(index: rawIdx, price: rawPrice)
        }
        let nearestIdx = Int(round(rawIdx))
        guard candles.indices.contains(nearestIdx) else {
            return ChartPoint(index: rawIdx, price: rawPrice)
        }
        let c = candles[nearestIdx]
        let candidates = [c.high, c.low, c.open, c.close]
        let bestPrice = candidates.min(by: { abs($0 - rawPrice) < abs($1 - rawPrice) }) ?? rawPrice
        return ChartPoint(index: Double(nearestIdx), price: bestPrice)
    }

    private func applyShiftAngleSnap(start: ChartPoint, end: ChartPoint, tool: DrawingTool, plotHeight: CGFloat, range: VisibleRange) -> ChartPoint {
        guard NSEvent.modifierFlags.contains(.shift),
              tool == .trendLine || tool == .parallelChannel else {
            return end
        }
        let p1 = CGPoint(x: range.x(forIndex: start.index), y: range.y(forPrice: start.price, topPadding: topPadding, plotHeight: plotHeight))
        let p2 = CGPoint(x: range.x(forIndex: end.index), y: range.y(forPrice: end.price, topPadding: topPadding, plotHeight: plotHeight))
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dist = hypot(dx, dy)
        guard dist > 4 else { return end }
        let angle = atan2(dy, dx)
        let snappedAngle = (angle / (.pi / 4.0)).rounded() * (.pi / 4.0)
        let snappedPt = CGPoint(x: p1.x + cos(snappedAngle) * dist, y: p1.y + sin(snappedAngle) * dist)
        return ChartPoint(
            index: range.index(forX: snappedPt.x),
            price: range.price(forY: snappedPt.y, topPadding: topPadding, plotHeight: plotHeight)
        )
    }

    // MARK: - Drawing Hit Testing (Select / Move / Resize Handles)

    private func hitTestDrawing(at pt: CGPoint, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange) -> DrawingEditHandle {
        let handleRadius: CGFloat = 14.0
        let hitTolerance: CGFloat = 13.0

        // Check in reverse order (topmost drawing first)
        for obj in store.currentDrawings.reversed() {
            let p1 = CGPoint(x: range.x(forIndex: obj.start.index), y: range.y(forPrice: obj.start.price, topPadding: topPadding, plotHeight: plotHeight))
            let p2 = CGPoint(x: range.x(forIndex: obj.end.index), y: range.y(forPrice: obj.end.price, topPadding: topPadding, plotHeight: plotHeight))

            if !obj.tool.isSinglePoint {
                if hypot(pt.x - p1.x, pt.y - p1.y) <= handleRadius {
                    return .startHandle(obj.id)
                }
                if hypot(pt.x - p2.x, pt.y - p2.y) <= handleRadius {
                    return .endHandle(obj.id)
                }
            }

            let hitBody: Bool
            switch obj.tool {
            case .horizontalLine:
                hitBody = abs(pt.y - p1.y) <= hitTolerance
            case .horizontalRay:
                hitBody = pt.x >= p1.x - 6 && abs(pt.y - p1.y) <= hitTolerance
            case .verticalLine:
                hitBody = abs(pt.x - p1.x) <= hitTolerance
            case .trendLine, .parallelChannel:
                hitBody = distanceFromPointToSegment(pt, p1, p2) <= hitTolerance + (obj.tool == .parallelChannel ? 30 : 0)
            case .rectangle, .priceRange, .fibRetracement:
                let rect = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: max(16, abs(p2.x - p1.x)), height: max(16, abs(p2.y - p1.y))).insetBy(dx: -6, dy: -6)
                hitBody = rect.contains(pt)
            case .longPosition, .shortPosition:
                let xMin = min(p1.x, p2.x) - 6
                let w = max(72, abs(p2.x - p1.x)) + 12
                let isLong = (obj.tool == .longPosition)
                let riskDist = max(abs(obj.end.price - obj.start.price), store.instrument.pipSize * 15)
                let slY = range.y(forPrice: isLong ? (obj.start.price - riskDist) : (obj.start.price + riskDist), topPadding: topPadding, plotHeight: plotHeight)
                let tpY = range.y(forPrice: isLong ? (obj.start.price + riskDist * obj.riskReward) : (obj.start.price - riskDist * obj.riskReward), topPadding: topPadding, plotHeight: plotHeight)
                let rect = CGRect(x: xMin, y: min(slY, tpY) - 6, width: w, height: abs(tpY - slY) + 12)
                hitBody = rect.contains(pt)
            case .textNote:
                let pill = CGRect(x: p1.x - 4, y: p1.y - 14, width: 104, height: 28)
                hitBody = pill.contains(pt)
            case .cursor:
                hitBody = false
            }

            if hitBody {
                return .moveBody(obj.id, origStart: obj.start, origEnd: obj.end)
            }
        }
        return .none
    }

    private func distanceFromPointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let vx = b.x - a.x
        let vy = b.y - a.y
        let wx = p.x - a.x
        let wy = p.y - a.y
        let lenSq = vx * vx + vy * vy
        if lenSq < 1e-6 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, (wx * vx + wy * vy) / lenSq))
        let proj = CGPoint(x: a.x + t * vx, y: a.y + t * vy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    // MARK: - Hover Cursors & Drag Handlers

    private func zoneFor(point: CGPoint, plotWidth: CGFloat, plotHeight: CGFloat) -> ChartDragZone {
        if point.x > plotWidth && point.y < topPadding + plotHeight { return .priceAxis }
        if point.x <= plotWidth && point.y >= topPadding + plotHeight { return .timeAxis }
        return .plot
    }

    private func updateHoverCursor(pt: CGPoint, plotWidth: CGFloat, plotHeight: CGFloat) {
        let z = zoneFor(point: pt, plotWidth: plotWidth, plotHeight: plotHeight)
        guard z != activeCursorZone else { return }
        if activeCursorZone != .none { NSCursor.pop() }
        activeCursorZone = z
        switch z {
        case .priceAxis: NSCursor.resizeUpDown.push()
        case .timeAxis: NSCursor.resizeLeftRight.push()
        case .plot: NSCursor.crosshair.push()
        case .none: break
        }
    }

    private func resetHoverCursor() {
        if activeCursorZone != .none {
            NSCursor.pop()
            activeCursorZone = .none
        }
    }

    private func handleDragChanged(value: DragGesture.Value, plotWidth: CGFloat, plotHeight: CGFloat, candles: [Candle], range: VisibleRange) {
        if activeDragZone == .none {
            activeDragZone = zoneFor(point: value.startLocation, plotWidth: plotWidth, plotHeight: plotHeight)
            lastPanTranslation = .zero

            if activeDragZone == .plot && store.activeTool == .cursor {
                let hit = hitTestDrawing(at: value.startLocation, plotWidth: plotWidth, plotHeight: plotHeight, range: range)
                activeEditHandle = hit
                switch hit {
                case .startHandle(let id), .endHandle(let id), .moveBody(let id, _, _):
                    store.selectedDrawingId = id
                    store.pushDrawingUndoSnapshot()
                case .none:
                    store.selectedDrawingId = nil
                }
            }
        }

        let dx = value.translation.width - lastPanTranslation.width
        let dy = value.translation.height - lastPanTranslation.height
        lastPanTranslation = value.translation

        // 1. Right Price Axis drag -> vertical zoom
        if activeDragZone == .priceAxis {
            store.scalePriceAxis(deltaY: dy, currentMin: range.minPrice, currentMax: range.maxPrice)
            return
        }

        // 2. Bottom Time Axis drag -> horizontal zoom
        if activeDragZone == .timeAxis {
            let factor = exp(-Double(dx) * 0.0065)
            store.zoom(factor: factor, anchorFraction: 0.92)
            return
        }

        // 3. Plot Area with Crosshair: either editing a drawing OR panning chart
        if store.activeTool == .cursor {
            switch activeEditHandle {
            case .startHandle(let id):
                if var obj = store.currentDrawings.first(where: { $0.id == id }) {
                    let raw = chartPoint(at: value.location, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: range)
                    obj.start = applyShiftAngleSnap(start: obj.end, end: raw, tool: obj.tool, plotHeight: plotHeight, range: range)
                    store.updateDrawing(obj, persist: false)
                }
                return
            case .endHandle(let id):
                if var obj = store.currentDrawings.first(where: { $0.id == id }) {
                    let raw = chartPoint(at: value.location, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: range)
                    obj.end = applyShiftAngleSnap(start: obj.start, end: raw, tool: obj.tool, plotHeight: plotHeight, range: range)
                    store.updateDrawing(obj, persist: false)
                }
                return
            case .moveBody(let id, let origStart, let origEnd):
                if var obj = store.currentDrawings.first(where: { $0.id == id }) {
                    let deltaIdx = Double(value.translation.width / max(range.candleStepX, 0.5))
                    let pricePerPx = (range.maxPrice - range.minPrice) / Double(max(plotHeight, 1.0))
                    let deltaPrice = -Double(value.translation.height) * pricePerPx
                    obj.start = ChartPoint(index: origStart.index + deltaIdx, price: origStart.price + deltaPrice)
                    obj.end = ChartPoint(index: origEnd.index + deltaIdx, price: origEnd.price + deltaPrice)
                    store.updateDrawing(obj, persist: false)
                }
                return
            case .none:
                let deltaBars = -Double(dx / max(range.candleStepX, 0.5))
                store.pan(deltaBars: deltaBars)
                if !store.isAutoPriceScale {
                    let pricePerPixel = (range.maxPrice - range.minPrice) / Double(max(plotHeight, 1.0))
                    store.panPriceAxis(deltaPrice: Double(dy) * pricePerPixel, currentMin: range.minPrice, currentMax: range.maxPrice)
                }
                return
            }
        }

        // 4. Active Drawing Creation (Supports BOTH TradingView Click-Move-Click AND Click-Drag!)
        let startPt = chartPoint(at: value.startLocation, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: range)
        let rawCurPt = chartPoint(at: value.location, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: range)

        if isAwaitingSecondPoint, var draft = draftDrawing {
            // Second click in Click-Move-Click flow: allow fine adjustment until mouse-up
            draft.end = applyShiftAngleSnap(start: draft.start, end: rawCurPt, tool: draft.tool, plotHeight: plotHeight, range: range)
            draftDrawing = draft
            return
        }

        if draftDrawing == nil {
            let snappedEnd = store.activeTool.isSinglePoint
                ? startPt
                : applyShiftAngleSnap(start: startPt, end: rawCurPt, tool: store.activeTool, plotHeight: plotHeight, range: range)
            draftDrawing = DrawingObject(
                id: UUID(),
                tool: store.activeTool,
                start: startPt,
                end: snappedEnd,
                colorPresetId: store.activeColorPresetId,
                label: store.activeTool == .textNote ? store.pendingNoteText : store.activeTool.rawValue
            )
        } else if var draft = draftDrawing {
            draft.end = store.activeTool.isSinglePoint
                ? draft.start
                : applyShiftAngleSnap(start: draft.start, end: rawCurPt, tool: draft.tool, plotHeight: plotHeight, range: range)
            draftDrawing = draft
        }
    }

    private func handleDragEnded(value: DragGesture.Value, plotWidth: CGFloat, plotHeight: CGFloat, candles: [Candle], range: VisibleRange) {
        defer {
            activeDragZone = .none
            activeEditHandle = .none
            lastPanTranslation = .zero
        }

        switch activeEditHandle {
        case .startHandle(let id), .endHandle(let id), .moveBody(let id, _, _):
            if let obj = store.currentDrawings.first(where: { $0.id == id }) {
                store.updateDrawing(obj, persist: true)
            }
            return
        case .none:
            break
        }

        guard activeDragZone == .plot, store.activeTool != .cursor else { return }
        guard let finalDrawing = draftDrawing else { return }

        let dragDist = hypot(value.translation.width, value.translation.height)

        // Single-point tools place immediately on click
        if finalDrawing.tool.isSinglePoint {
            store.addDrawing(finalDrawing)
            store.selectedDrawingId = finalDrawing.id
            draftDrawing = nil
            isAwaitingSecondPoint = false
            store.activeTool = .cursor
            return
        }

        // Two-point tools:
        // - If we were already waiting for Point 2 -> commit on this 2nd click!
        // - If user clicked & released (< 6pt drag) for Point 1 -> enter TradingView Click-Move-Click mode!
        // - If user clicked & dragged (>= 6pt) -> commit cleanly right away!
        if isAwaitingSecondPoint || dragDist >= 6.0 {
            store.addDrawing(finalDrawing)
            store.selectedDrawingId = finalDrawing.id
            draftDrawing = nil
            isAwaitingSecondPoint = false
            store.activeTool = .cursor
        } else {
            isAwaitingSecondPoint = true
        }
    }

    // MARK: - Canvas Rendering

    private func drawChart(
        ctx: inout GraphicsContext,
        size: CGSize,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        candles: [Candle],
        range: VisibleRange,
        theme t: AppTheme
    ) {
        let plotRect = CGRect(x: 0, y: topPadding, width: plotWidth, height: plotHeight)
        let cfg = store.indicatorConfig
        let conceptOn = store.isStudyVisible(.concept)
        let flowOn = store.isStudyVisible(.orderFlow)
        let revOn = store.isStudyVisible(.reversalTargets)
        let toolkitOn = store.isStudyVisible(.sessionToolkits)
        let sidewayOn = store.isStudyVisible(.sidewayDetector)

        drawGridAndAxes(ctx: &ctx, size: size, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: range, theme: t)

        ctx.drawLayer { layer in
            layer.clip(to: Path(plotRect))

            if ((conceptOn && cfg.conceptShowVolumeProfile) || toolkitOn) && candles.indices.contains(range.firstCandle) {
                let slice = candles[range.firstCandle...range.lastCandle]
                if let vp = IndicatorEngine.computeVolumeProfile(
                    candles: slice,
                    binCount: cfg.conceptProfileBins,
                    valueAreaPercent: cfg.toolkitValueAreaPercent
                ) {
                    drawVolumeProfile(ctx: &layer, vp: vp, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
                }
            }

            if conceptOn && cfg.conceptShowOrderBlocks {
                drawOrderBlocks(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
            }
            if sidewayOn && cfg.sidewayShowScalpZones {
                drawScalpZones(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
            }
            if flowOn && cfg.orderFlowShowVolumeZones {
                drawVolumeZones(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
            }
            if flowOn && cfg.orderFlowShowFVG {
                drawFVGs(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range)
            }
            if flowOn && cfg.orderFlowShowProtectedLevels {
                drawProtectedLevels(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
            }
            if toolkitOn && cfg.toolkitShowPivots, let piv = store.computed.pivots {
                drawPivots(ctx: &layer, pivots: piv, plotWidth: plotWidth, plotHeight: plotHeight, range: range)
            }
            if revOn {
                if cfg.revShowBollinger { drawBollingerBands(ctx: &layer, plotHeight: plotHeight, range: range, theme: t) }
                if cfg.revShowVolatilityBand { drawVolatilityBand(ctx: &layer, plotHeight: plotHeight, range: range, theme: t) }
                if cfg.revShowPrevHighLow { drawPreviousHighLow(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t) }
            }
            if flowOn && cfg.orderFlowShowVolumeHistogram {
                drawVolumeBars(ctx: &layer, candles: candles, plotHeight: plotHeight, range: range, theme: t)
            }

            drawCandlesticks(ctx: &layer, candles: candles, plotHeight: plotHeight, range: range, theme: t)

            if conceptOn {
                if cfg.conceptShowEMA20 { drawLineSeries(ctx: &layer, series: store.computed.ema20, color: t.telemetryBlue, lineWidth: 1.5, plotHeight: plotHeight, range: range) }
                if cfg.conceptShowEMA50 { drawLineSeries(ctx: &layer, series: store.computed.ema50, color: t.amber, lineWidth: 1.5, plotHeight: plotHeight, range: range) }
                if cfg.conceptShowEMA200 { drawLineSeries(ctx: &layer, series: store.computed.ema200, color: .purple, lineWidth: 1.7, plotHeight: plotHeight, range: range) }
            }
            if conceptOn && cfg.conceptShowStructure {
                drawStructureBreaks(ctx: &layer, plotHeight: plotHeight, range: range, theme: t)
            }
            if conceptOn && cfg.conceptShowDivergences {
                drawRSIDivergences(ctx: &layer, plotHeight: plotHeight, range: range, theme: t)
            }
            if flowOn && cfg.orderFlowShowImpulse {
                drawAcceleratorMarkers(ctx: &layer, candles: candles, showStars: cfg.orderFlowShowWicklessStars, plotHeight: plotHeight, range: range, theme: t)
            }
            if revOn {
                drawReversalTargets(ctx: &layer, candles: candles, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
            }
            if store.showBacktestSignalsOnChart {
                drawBacktestSignals(ctx: &layer, candles: candles, plotHeight: plotHeight, range: range, theme: t)
            }

            drawPriceAlerts(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)
            drawSamplePositions(ctx: &layer, plotWidth: plotWidth, plotHeight: plotHeight, range: range, theme: t)

            for d in store.currentDrawings {
                let isSelected = (d.id == store.selectedDrawingId)
                let isHovered = (d.id == hoveredDrawingId)
                drawUserObject(ctx: &layer, obj: d, plotWidth: plotWidth, plotHeight: plotHeight, range: range, isDraft: false, isSelected: isSelected || isHovered, theme: t)
            }
            if let draft = draftDrawing {
                drawUserObject(ctx: &layer, obj: draft, plotWidth: plotWidth, plotHeight: plotHeight, range: range, isDraft: true, isSelected: true, theme: t)
            } else if store.activeTool != .cursor, let pt = hoverLocation, pt.x >= 0, pt.x <= plotWidth, pt.y >= topPadding, pt.y <= topPadding + plotHeight {
                // Live pre-placement snap dot (shows exact candle OHLC snap when Magnet is ON)
                let snapped = chartPoint(at: pt, plotWidth: plotWidth, plotHeight: plotHeight, candles: candles, range: range)
                let sx = range.x(forIndex: snapped.index)
                let sy = range.y(forPrice: snapped.price, topPadding: topPadding, plotHeight: plotHeight)
                let ring = CGRect(x: sx - 5.5, y: sy - 5.5, width: 11, height: 11)
                layer.fill(Path(ellipseIn: ring), with: .color(t.accent.opacity(0.28)))
                layer.stroke(Path(ellipseIn: ring), with: .color(t.accent), lineWidth: 1.6)
            }

            if let last = candles.last {
                let y = range.y(forPrice: last.close, topPadding: topPadding, plotHeight: plotHeight)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
                layer.stroke(p, with: .color((last.isBullish ? t.bull : t.bear).opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }

        // Live Price Pill + Bar Close Countdown on Right Axis (TradingView style!)
        if let last = candles.last {
            let y = range.y(forPrice: last.close, topPadding: topPadding, plotHeight: plotHeight)
            if y >= topPadding && y <= topPadding + plotHeight {
                let col = last.isBullish ? t.bull : t.bear
                let hasTimer = !store.candleCountdownText.isEmpty
                let pillH: CGFloat = hasTimer ? 31 : 20
                let pill = CGRect(x: plotWidth + 3, y: y - (hasTimer ? 11 : 10), width: rightAxisWidth - 6, height: pillH)
                ctx.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(col))
                ctx.draw(
                    Text(store.instrument.formatPrice(last.close))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white),
                    at: CGPoint(x: pill.midX, y: pill.minY + 9.5)
                )
                if hasTimer {
                    ctx.draw(
                        Text(store.candleCountdownText)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88)),
                        at: CGPoint(x: pill.midX, y: pill.minY + 22.5)
                    )
                }
            }
        }

        // Crosshair + Right Price Pill + Bottom Date/Time Pill
        if let pt = hoverLocation, pt.x >= 0, pt.x <= plotWidth, pt.y >= topPadding, pt.y <= topPadding + plotHeight {
            let crossCol = t.primaryText.opacity(0.28)
            var vLine = Path(); vLine.move(to: CGPoint(x: pt.x, y: topPadding)); vLine.addLine(to: CGPoint(x: pt.x, y: topPadding + plotHeight))
            ctx.stroke(vLine, with: .color(crossCol), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            var hLine = Path(); hLine.move(to: CGPoint(x: 0, y: pt.y)); hLine.addLine(to: CGPoint(x: plotWidth, y: pt.y))
            ctx.stroke(hLine, with: .color(crossCol), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            let hoverPrice = range.price(forY: pt.y, topPadding: topPadding, plotHeight: plotHeight)
            let pRect = CGRect(x: plotWidth + 3, y: pt.y - 10, width: rightAxisWidth - 6, height: 20)
            ctx.fill(Path(roundedRect: pRect, cornerRadius: 4), with: .color(t.primaryText))
            ctx.draw(
                Text(store.instrument.formatPrice(hoverPrice))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(t.chartBg),
                at: CGPoint(x: pRect.midX, y: pRect.midY)
            )

            // Bottom Date/Time crosshair pill
            let hIdx = Int(round(range.index(forX: pt.x)))
            if candles.indices.contains(hIdx) {
                let df = DateFormatter()
                df.dateFormat = store.timeframe == .d1 ? "MMM d, yyyy" : "MMM d HH:mm"
                let tText = df.string(from: candles[hIdx].timestamp)
                let tW: CGFloat = 94
                let tX = max(4, min(plotWidth - tW - 4, pt.x - tW * 0.5))
                let tRect = CGRect(x: tX, y: topPadding + plotHeight + 3, width: tW, height: 20)
                ctx.fill(Path(roundedRect: tRect, cornerRadius: 4), with: .color(t.primaryText))
                ctx.draw(
                    Text(tText)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(t.chartBg),
                    at: CGPoint(x: tRect.midX, y: tRect.midY)
                )
            }
        }
    }

    private func drawGridAndAxes(ctx: inout GraphicsContext, size: CGSize, plotWidth: CGFloat, plotHeight: CGFloat, candles: [Candle], range: VisibleRange, theme t: AppTheme) {
        let hLevels = 7
        for i in 0...hLevels {
            let frac = CGFloat(i) / CGFloat(hLevels)
            let y = topPadding + plotHeight * frac
            var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(line, with: .color(t.gridLine), lineWidth: 1)

            let p = range.maxPrice - Double(frac) * (range.maxPrice - range.minPrice)
            ctx.draw(Text(store.instrument.formatPrice(p)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(t.secondaryText), at: CGPoint(x: plotWidth + rightAxisWidth * 0.5, y: y))
        }

        var rightSep = Path(); rightSep.move(to: CGPoint(x: plotWidth, y: 0)); rightSep.addLine(to: CGPoint(x: plotWidth, y: size.height))
        ctx.stroke(rightSep, with: .color(t.border), lineWidth: 1)

        var botSep = Path(); botSep.move(to: CGPoint(x: 0, y: topPadding + plotHeight)); botSep.addLine(to: CGPoint(x: size.width, y: topPadding + plotHeight))
        ctx.stroke(botSep, with: .color(t.border), lineWidth: 1)

        let strideBars = max(6, Int(store.visibleCandleCount / 7.0))
        let df = DateFormatter()
        df.dateFormat = store.timeframe == .d1 ? "MMM d" : "HH:mm"
        var idx = (range.firstCandle / strideBars) * strideBars
        while idx <= range.lastCandle {
            if candles.indices.contains(idx) {
                let x = range.x(forIndex: Double(idx))
                if x >= 24 && x <= plotWidth - 24 {
                    var vl = Path(); vl.move(to: CGPoint(x: x, y: topPadding)); vl.addLine(to: CGPoint(x: x, y: topPadding + plotHeight))
                    ctx.stroke(vl, with: .color(t.gridLine), lineWidth: 1)
                    ctx.draw(Text(df.string(from: candles[idx].timestamp)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(t.secondaryText), at: CGPoint(x: x, y: topPadding + plotHeight + 13))
                }
            }
            idx += strideBars
        }
    }

    private func drawVolumeBars(ctx: inout GraphicsContext, candles: [Candle], plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        guard !candles.isEmpty else { return }
        let maxVol = (range.firstCandle...range.lastCandle).map { candles[$0].volume }.max() ?? 1.0
        let maxBarH = plotHeight * 0.14
        let w = max(1.5, range.candleStepX * 0.62)
        let baseY = topPadding + plotHeight
        for i in range.firstCandle...range.lastCandle {
            let c = candles[i]
            let x = range.x(forIndex: Double(i))
            let h = CGFloat(c.volume / max(maxVol, 1.0)) * maxBarH
            ctx.fill(Path(CGRect(x: x - w * 0.5, y: baseY - h, width: w, height: h)), with: .color((c.isBullish ? t.bull : t.bear).opacity(0.20)))
        }
    }

    private func drawCandlesticks(ctx: inout GraphicsContext, candles: [Candle], plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        guard !candles.isEmpty else { return }
        let bodyW = max(2.2, min(18.0, range.candleStepX * 0.68))
        for i in range.firstCandle...range.lastCandle {
            let c = candles[i]
            let x = range.x(forIndex: Double(i))
            let yHigh = range.y(forPrice: c.high, topPadding: topPadding, plotHeight: plotHeight)
            let yLow = range.y(forPrice: c.low, topPadding: topPadding, plotHeight: plotHeight)
            let yTop = range.y(forPrice: c.bodyTop, topPadding: topPadding, plotHeight: plotHeight)
            let yBot = range.y(forPrice: c.bodyBottom, topPadding: topPadding, plotHeight: plotHeight)
            let col = c.isBullish ? t.bull : t.bear
            var wick = Path(); wick.move(to: CGPoint(x: x, y: yHigh)); wick.addLine(to: CGPoint(x: x, y: yLow))
            ctx.stroke(wick, with: .color(col), lineWidth: 1.15)
            ctx.fill(Path(roundedRect: CGRect(x: x - bodyW * 0.5, y: yTop, width: bodyW, height: max(1.3, yBot - yTop)), cornerRadius: 0.8), with: .color(col))
        }
    }

    private func drawLineSeries(ctx: inout GraphicsContext, series: [Double?], color: Color, lineWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange) {
        guard !series.isEmpty else { return }
        var path = Path(); var started = false
        let lo = max(0, range.firstCandle - 1); let hi = min(series.count - 1, range.lastCandle + 1)
        for i in lo...hi {
            guard let val = series[i] else { started = false; continue }
            let pt = CGPoint(x: range.x(forIndex: Double(i)), y: range.y(forPrice: val, topPadding: topPadding, plotHeight: plotHeight))
            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawBollingerBands(ctx: inout GraphicsContext, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        let upper = store.computed.bbUpper; let mid = store.computed.bbMiddle; let lower = store.computed.bbLower
        guard upper.count == lower.count, !upper.isEmpty else { return }
        let lo = max(0, range.firstCandle); let hi = min(upper.count - 1, range.lastCandle)
        var uPts: [CGPoint] = []; var lPts: [CGPoint] = []
        for i in lo...hi {
            if let u = upper[i], let l = lower[i] {
                let x = range.x(forIndex: Double(i))
                uPts.append(CGPoint(x: x, y: range.y(forPrice: u, topPadding: topPadding, plotHeight: plotHeight)))
                lPts.append(CGPoint(x: x, y: range.y(forPrice: l, topPadding: topPadding, plotHeight: plotHeight)))
            }
        }
        if uPts.count >= 2 {
            var fill = Path(); fill.move(to: uPts[0])
            for p in uPts.dropFirst() { fill.addLine(to: p) }
            for p in lPts.reversed() { fill.addLine(to: p) }
            fill.closeSubpath()
            ctx.fill(fill, with: .color(t.accent.opacity(0.08)))
        }
        drawLineSeries(ctx: &ctx, series: upper, color: t.accent.opacity(0.6), lineWidth: 1.0, plotHeight: plotHeight, range: range)
        drawLineSeries(ctx: &ctx, series: mid, color: t.accent.opacity(0.35), lineWidth: 1.0, plotHeight: plotHeight, range: range)
        drawLineSeries(ctx: &ctx, series: lower, color: t.accent.opacity(0.6), lineWidth: 1.0, plotHeight: plotHeight, range: range)
    }

    private func drawPreviousHighLow(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        if let ph = store.computed.sideway.prevSessionHigh {
            let y = range.y(forPrice: ph, topPadding: topPadding, plotHeight: plotHeight)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(t.bear.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ctx.draw(Text("PDH").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(t.bear), at: CGPoint(x: plotWidth - 22, y: y - 8))
        }
        if let pl = store.computed.sideway.prevSessionLow {
            let y = range.y(forPrice: pl, topPadding: topPadding, plotHeight: plotHeight)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(t.bull.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ctx.draw(Text("PDL").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(t.bull), at: CGPoint(x: plotWidth - 22, y: y + 8))
        }
    }

    private func drawVolumeProfile(ctx: inout GraphicsContext, vp: VolumeProfileResult, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        let maxW = plotWidth * 0.15
        for bin in vp.bins {
            let yTop = range.y(forPrice: bin.high, topPadding: topPadding, plotHeight: plotHeight)
            let yBot = range.y(forPrice: bin.low, topPadding: topPadding, plotHeight: plotHeight)
            let h = max(1.0, yBot - yTop - 0.8)
            let totalW = CGFloat(bin.totalVolume / vp.maxVolume) * maxW
            let buyW = totalW * CGFloat(bin.buyVolume / max(bin.totalVolume, 1e-6))
            let sellW = totalW - buyW
            let inVA = bin.low >= vp.valPrice && bin.high <= vp.vahPrice
            let alpha: Double = inVA ? 0.25 : 0.10
            ctx.fill(Path(CGRect(x: plotWidth - totalW, y: yTop, width: buyW, height: h)), with: .color(t.bull.opacity(alpha)))
            ctx.fill(Path(CGRect(x: plotWidth - sellW, y: yTop, width: sellW, height: h)), with: .color(t.bear.opacity(alpha)))
        }
        let pocY = range.y(forPrice: vp.pocPrice, topPadding: topPadding, plotHeight: plotHeight)
        var pocPath = Path(); pocPath.move(to: CGPoint(x: plotWidth - maxW * 1.15, y: pocY)); pocPath.addLine(to: CGPoint(x: plotWidth, y: pocY))
        ctx.stroke(pocPath, with: .color(t.amber.opacity(0.9)), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
        ctx.draw(Text("POC").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(t.amber), at: CGPoint(x: plotWidth - maxW - 14, y: pocY))
    }

    private func drawVolatilityBand(ctx: inout GraphicsContext, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        let upper = store.computed.volatilityUpper
        let lower = store.computed.volatilityLower
        let trend = store.computed.volatilityTrend
        guard upper.count == lower.count, !upper.isEmpty else { return }
        let lo = max(0, range.firstCandle)
        let hi = min(upper.count - 1, range.lastCandle)

        var bullPath = Path(); var bullStarted = false
        var bearPath = Path(); var bearStarted = false
        for i in lo...hi {
            let x = range.x(forIndex: Double(i))
            if trend[i] >= 0, let l = lower[i] {
                let pt = CGPoint(x: x, y: range.y(forPrice: l, topPadding: topPadding, plotHeight: plotHeight))
                if !bullStarted { bullPath.move(to: pt); bullStarted = true } else { bullPath.addLine(to: pt) }
                bearStarted = false
            } else if trend[i] < 0, let u = upper[i] {
                let pt = CGPoint(x: x, y: range.y(forPrice: u, topPadding: topPadding, plotHeight: plotHeight))
                if !bearStarted { bearPath.move(to: pt); bearStarted = true } else { bearPath.addLine(to: pt) }
                bullStarted = false
            }
        }
        ctx.stroke(bullPath, with: .color(t.bull.opacity(0.85)), lineWidth: 1.8)
        ctx.stroke(bearPath, with: .color(t.bear.opacity(0.85)), lineWidth: 1.8)
    }

    private func drawOrderBlocks(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for ob in store.computed.orderBlocks {
            let x1 = range.x(forIndex: Double(ob.startIndex))
            if x1 > plotWidth { continue }
            let yTop = range.y(forPrice: ob.top, topPadding: topPadding, plotHeight: plotHeight)
            let yBot = range.y(forPrice: ob.bottom, topPadding: topPadding, plotHeight: plotHeight)
            let rect = CGRect(x: max(0, x1), y: yTop, width: max(8, plotWidth - max(0, x1)), height: max(2, yBot - yTop))
            let base = ob.isBullish ? t.bull : t.bear
            ctx.fill(Path(rect), with: .color(base.opacity(ob.mitigated ? 0.04 : 0.13)))
            ctx.stroke(Path(rect), with: .color(base.opacity(ob.mitigated ? 0.16 : 0.48)), lineWidth: 0.9)
            if !ob.mitigated {
                let lbl = String(format: "%@ %.0f%%", ob.isBullish ? "OB+" : "OB-", ob.pressurePercent)
                ctx.draw(Text(lbl).font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(base), at: CGPoint(x: rect.minX + 34, y: rect.midY))
            }
        }
    }

    private func drawScalpZones(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for sz in store.computed.scalpZones {
            let x1 = range.x(forIndex: Double(sz.startIndex))
            let x2 = min(plotWidth, range.x(forIndex: Double(sz.endIndex)))
            if x1 > plotWidth || x2 < 0 { continue }
            let yTop = range.y(forPrice: sz.top, topPadding: topPadding, plotHeight: plotHeight)
            let yBot = range.y(forPrice: sz.bottom, topPadding: topPadding, plotHeight: plotHeight)
            let rect = CGRect(x: max(0, x1), y: yTop, width: max(18, x2 - max(0, x1)), height: max(4, yBot - yTop))
            let col = t.amber
            ctx.fill(Path(rect), with: .color(col.opacity(0.14)))
            ctx.stroke(Path(rect), with: .color(col.opacity(0.75)), style: StrokeStyle(lineWidth: 1.1, dash: [4, 2]))
            ctx.draw(Text(String(format: "SCALP · %.0f%%", sz.pressurePercent)).font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: rect.minX + 42, y: rect.minY - 7))
        }
    }

    private func drawVolumeZones(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for vz in store.computed.volumeZones {
            let x1 = range.x(forIndex: Double(vz.startIndex))
            if x1 > plotWidth { continue }
            let yTop = range.y(forPrice: vz.top, topPadding: topPadding, plotHeight: plotHeight)
            let yBot = range.y(forPrice: vz.bottom, topPadding: topPadding, plotHeight: plotHeight)
            let rect = CGRect(x: max(0, x1), y: yTop, width: max(10, plotWidth - max(0, x1)), height: max(2, yBot - yTop))
            let col = Color.purple
            ctx.fill(Path(rect), with: .color(col.opacity(0.08)))
            ctx.stroke(Path(rect), with: .color(col.opacity(0.32)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            ctx.draw(Text(String(format: "VOL %.1fx", vz.volumeMultiple)).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(col.opacity(0.8)), at: CGPoint(x: rect.minX + 28, y: rect.midY))
        }
    }

    private func drawProtectedLevels(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for pl in store.computed.protectedLevels {
            let x1 = range.x(forIndex: Double(pl.startIndex))
            if x1 > plotWidth { continue }
            let y = range.y(forPrice: pl.price, topPadding: topPadding, plotHeight: plotHeight)
            let col = pl.isHigh ? t.bear.opacity(0.65) : t.bull.opacity(0.65)
            var p = Path(); p.move(to: CGPoint(x: max(0, x1), y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 0.9, dash: [6, 3]))
            ctx.draw(Text(pl.isHigh ? "Prot H" : "Prot L").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: plotWidth - 26, y: pl.isHigh ? y - 7 : y + 7))
        }
    }

    private func drawRSIDivergences(ctx: inout GraphicsContext, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for div in store.computed.rsiDivergences {
            let x1 = range.x(forIndex: Double(div.startIndex))
            let x2 = range.x(forIndex: Double(div.endIndex))
            let y1 = range.y(forPrice: div.startPrice, topPadding: topPadding, plotHeight: plotHeight)
            let y2 = range.y(forPrice: div.endPrice, topPadding: topPadding, plotHeight: plotHeight)
            let col = div.isBullish ? t.bull : t.bear
            var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
            ctx.draw(Text(div.label).font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: x2, y: div.isBullish ? y2 + 12 : y2 - 12))
        }
    }

    private func drawFVGs(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange) {
        for fvg in store.computed.fvgs {
            let x1 = range.x(forIndex: Double(fvg.startIndex))
            if x1 > plotWidth { continue }
            let yTop = range.y(forPrice: fvg.top, topPadding: topPadding, plotHeight: plotHeight)
            let yBot = range.y(forPrice: fvg.bottom, topPadding: topPadding, plotHeight: plotHeight)
            let width = min(plotWidth - max(0, x1), range.candleStepX * 26)
            let rect = CGRect(x: max(0, x1), y: yTop, width: max(6, width), height: max(2, yBot - yTop))
            let col = fvg.isBullish ? Color.cyan : Color.orange
            ctx.fill(Path(rect), with: .color(col.opacity(0.14)))
            ctx.draw(Text("FVG").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(col.opacity(0.85)), at: CGPoint(x: rect.minX + 16, y: rect.midY))
        }
    }

    private func drawAcceleratorMarkers(ctx: inout GraphicsContext, candles: [Candle], showStars: Bool, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for m in store.computed.accelerators {
            guard candles.indices.contains(m.index) else { continue }
            let bar = candles[m.index]
            let x = range.x(forIndex: Double(m.index))
            let y = m.isBullish ? range.y(forPrice: bar.low, topPadding: topPadding, plotHeight: plotHeight) + 14 : range.y(forPrice: bar.high, topPadding: topPadding, plotHeight: plotHeight) - 14
            let col = m.isBullish ? t.bull : t.bear
            let labelText = (showStars && m.isWickless) ? "\(m.caption)★" : m.caption
            let w: CGFloat = (showStars && m.isWickless) ? 44 : 36
            let pill = CGRect(x: x - w * 0.5, y: y - 7.5, width: w, height: 15)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(col.opacity(m.isPlus ? 0.92 : 0.18)))
            if !m.isPlus {
                ctx.stroke(Path(roundedRect: pill, cornerRadius: 4), with: .color(col.opacity(0.75)), lineWidth: 0.9)
            }
            ctx.draw(
                Text(labelText)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(m.isPlus ? .white : col),
                at: CGPoint(x: pill.midX, y: pill.midY)
            )
        }
    }

    private func drawReversalTargets(ctx: inout GraphicsContext, candles: [Candle], plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for sig in store.computed.reversalSignals {
            guard candles.indices.contains(sig.index) else { continue }
            let bar = candles[sig.index]
            let x = range.x(forIndex: Double(sig.index))
            let y = sig.isBullish ? range.y(forPrice: bar.low, topPadding: topPadding, plotHeight: plotHeight) + 16 : range.y(forPrice: bar.high, topPadding: topPadding, plotHeight: plotHeight) - 16
            let col = sig.isBullish ? t.bull : t.bear
            let pill = CGRect(x: x - 19, y: y - 8, width: 38, height: 16)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(col))
            ctx.draw(Text(sig.isBullish ? "BUY" : "SELL").font(.system(size: 8.5, weight: .black, design: .monospaced)).foregroundStyle(.white), at: CGPoint(x: pill.midX, y: pill.midY))
        }
        if let latest = store.computed.reversalSignals.last {
            let xStart = max(0, min(plotWidth - 96, range.x(forIndex: Double(latest.index))))
            let levels: [(String, Double, Color)] = [
                ("ENTRY", latest.entry, t.accent),
                ("SL", latest.stopLoss, t.bear),
                ("TP1", latest.tp1, t.bull.opacity(0.78)),
                ("TP2", latest.tp2, t.bull.opacity(0.90)),
                ("TP3", latest.tp3, t.bull)
            ]
            for (lbl, price, col) in levels {
                let y = range.y(forPrice: price, topPadding: topPadding, plotHeight: plotHeight)
                guard y >= topPadding - 6 && y <= topPadding + plotHeight + 6 else { continue }
                var lp = Path()
                lp.move(to: CGPoint(x: xStart, y: y))
                lp.addLine(to: CGPoint(x: plotWidth, y: y))
                ctx.stroke(lp, with: .color(col), style: StrokeStyle(lineWidth: lbl == "ENTRY" ? 1.1 : 1.0, dash: [4, 3]))

                let tagText = "\(lbl) \(store.instrument.formatPrice(price))"
                let tagWidth = max(78, CGFloat(tagText.count) * 5.8 + 12)
                let tagX = min(plotWidth - tagWidth - 4, max(xStart + 4, plotWidth - tagWidth - 6))
                let pillRect = CGRect(x: tagX, y: y - 8, width: tagWidth, height: 16)
                ctx.fill(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(col.opacity(t.isDark ? 0.88 : 0.94)))
                ctx.draw(
                    Text(tagText)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white),
                    at: CGPoint(x: pillRect.midX, y: pillRect.midY)
                )
            }
        }
    }

    private func drawStructureBreaks(ctx: inout GraphicsContext, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for br in store.computed.structureBreaks {
            let x1 = range.x(forIndex: Double(br.fromIndex))
            let x2 = range.x(forIndex: Double(br.index))
            let y = range.y(forPrice: br.price, topPadding: topPadding, plotHeight: plotHeight)
            let col = br.isBullish ? t.bull : t.bear
            var p = Path(); p.move(to: CGPoint(x: x1, y: y)); p.addLine(to: CGPoint(x: x2, y: y))
            ctx.stroke(p, with: .color(col.opacity(0.85)), style: StrokeStyle(lineWidth: 1.1, dash: [3, 2]))
            ctx.draw(Text(br.label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: (x1 + x2) * 0.5, y: br.isBullish ? y - 8 : y + 8))
        }
    }

    private func drawPivots(ctx: inout GraphicsContext, pivots: PivotLevels, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange) {
        let levels: [(String, Double, Color)] = [
            ("R5", pivots.r5, .pink.opacity(0.85)),
            ("R4", pivots.r4, .red.opacity(0.75)),
            ("R3", pivots.r3, .orange.opacity(0.75)),
            ("R2", pivots.r2, .yellow.opacity(0.65)),
            ("S2", pivots.s2, .cyan.opacity(0.65)),
            ("S3", pivots.s3, .mint.opacity(0.75)),
            ("S4", pivots.s4, .green.opacity(0.75)),
            ("S5", pivots.s5, .teal.opacity(0.85))
        ]
        for (lbl, price, col) in levels {
            let y = range.y(forPrice: price, topPadding: topPadding, plotHeight: plotHeight)
            var p = Path(); p.move(to: CGPoint(x: plotWidth * 0.58, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 0.9, dash: [2, 3]))
            ctx.draw(Text("\(pivots.kind == .camarilla ? "C" : "F")-\(lbl)").font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: plotWidth * 0.58 - 18, y: y))
        }
    }

    private func drawBacktestSignals(ctx: inout GraphicsContext, candles: [Candle], plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for tr in store.backtestReport.trades {
            guard candles.indices.contains(tr.entryIndex) else { continue }
            let bar = candles[tr.entryIndex]
            let x = range.x(forIndex: Double(tr.entryIndex))
            let y = tr.isBuy ? range.y(forPrice: bar.low, topPadding: topPadding, plotHeight: plotHeight) + 12 : range.y(forPrice: bar.high, topPadding: topPadding, plotHeight: plotHeight) - 12
            let col = tr.isBuy ? t.bull : t.bear
            var tri = Path()
            if tr.isBuy { tri.move(to: CGPoint(x: x, y: y - 5)); tri.addLine(to: CGPoint(x: x - 5, y: y + 4)); tri.addLine(to: CGPoint(x: x + 5, y: y + 4)) }
            else { tri.move(to: CGPoint(x: x, y: y + 5)); tri.addLine(to: CGPoint(x: x - 5, y: y - 4)); tri.addLine(to: CGPoint(x: x + 5, y: y - 4)) }
            tri.closeSubpath()
            ctx.fill(tri, with: .color(col))
            ctx.draw(Text(String(format: "%@ %+.1fR", tr.isBuy ? "B" : "S", tr.rMultiple)).font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(tr.rMultiple >= 0 ? col : t.amber), at: CGPoint(x: x, y: tr.isBuy ? y + 12 : y - 12))
        }
    }

    private func drawPriceAlerts(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for alert in store.alerts where alert.instrument == store.instrument.rawValue && !alert.isTriggered {
            let y = range.y(forPrice: alert.targetPrice, topPadding: topPadding, plotHeight: plotHeight)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(t.accent.opacity(0.75)), style: StrokeStyle(lineWidth: 1.1, dash: [6, 3]))
            ctx.draw(Text("🔔 \(store.instrument.formatPrice(alert.targetPrice))").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(t.accent), at: CGPoint(x: plotWidth - 52, y: y - 9))
        }
    }

    private func drawSamplePositions(ctx: inout GraphicsContext, plotWidth: CGFloat, plotHeight: CGFloat, range: VisibleRange, theme t: AppTheme) {
        for pos in store.samplePositions where pos.instrument == store.instrument {
            let entryY = range.y(forPrice: pos.entryPrice, topPadding: topPadding, plotHeight: plotHeight)
            let col = pos.isBuy ? t.bull : t.bear
            var ep = Path(); ep.move(to: CGPoint(x: 0, y: entryY)); ep.addLine(to: CGPoint(x: plotWidth, y: entryY))
            ctx.stroke(ep, with: .color(col), lineWidth: 1.3)
            let pnl = pos.floatingPnL(currentPrice: store.lastPrice)
            let badgeRect = CGRect(x: 12, y: entryY - 10, width: 146, height: 19)
            ctx.fill(Path(roundedRect: badgeRect, cornerRadius: 5), with: .color(col))
            ctx.draw(Text(String(format: "%@ %.2f  %@$%.2f", pos.isBuy ? "BUY" : "SELL", pos.lots, pnl >= 0 ? "+" : "-", abs(pnl))).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white), at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
            if let sl = pos.stopLoss {
                let slY = range.y(forPrice: sl, topPadding: topPadding, plotHeight: plotHeight)
                var slp = Path(); slp.move(to: CGPoint(x: 0, y: slY)); slp.addLine(to: CGPoint(x: plotWidth, y: slY))
                ctx.stroke(slp, with: .color(t.bear.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let tp = pos.takeProfit {
                let tpY = range.y(forPrice: tp, topPadding: topPadding, plotHeight: plotHeight)
                var tpp = Path(); tpp.move(to: CGPoint(x: 0, y: tpY)); tpp.addLine(to: CGPoint(x: plotWidth, y: tpY))
                ctx.stroke(tpp, with: .color(t.bull.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }

        for ord in store.paperPendingOrders where ord.instrument == store.instrument {
            let y = range.y(forPrice: ord.entryPrice, topPadding: topPadding, plotHeight: plotHeight)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: plotWidth, y: y))
            ctx.stroke(p, with: .color(t.amber.opacity(0.85)), style: StrokeStyle(lineWidth: 1.15, dash: [6, 4]))
            let pill = CGRect(x: 12, y: y - 9, width: 152, height: 18)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(t.amber))
            ctx.draw(
                Text(String(format: "%@ %@ %.2f @ %@", ord.isBuy ? "BUY" : "SELL", ord.kind.rawValue.uppercased(), ord.lots, store.instrument.formatPrice(ord.entryPrice)))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white),
                at: CGPoint(x: pill.midX, y: pill.midY)
            )
        }
    }

    // MARK: - User Drawings + Interactive Selection Handles

    private func drawUserObject(
        ctx: inout GraphicsContext,
        obj: DrawingObject,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        range: VisibleRange,
        isDraft: Bool,
        isSelected: Bool,
        theme t: AppTheme
    ) {
        let p1 = CGPoint(x: range.x(forIndex: obj.start.index), y: range.y(forPrice: obj.start.price, topPadding: topPadding, plotHeight: plotHeight))
        let p2 = CGPoint(x: range.x(forIndex: obj.end.index), y: range.y(forPrice: obj.end.price, topPadding: topPadding, plotHeight: plotHeight))
        let col = obj.color
        let strokeStyle = StrokeStyle(lineWidth: isSelected ? 2.2 : 1.7, dash: isDraft ? [4, 3] : [])

        switch obj.tool {
        case .cursor: break
        case .trendLine:
            var path = Path(); path.move(to: p1); path.addLine(to: p2)
            ctx.stroke(path, with: .color(col), style: strokeStyle)
            if isDraft || isSelected {
                let diff = obj.end.price - obj.start.price
                let pips = diff / store.instrument.pipSize
                let bars = abs(Int(round(obj.end.index - obj.start.index)))
                if hypot(p2.x - p1.x, p2.y - p1.y) > 12 {
                    let readout = String(format: "%+.1fp · %db", pips, bars)
                    let pillW = max(72, CGFloat(readout.count) * 5.6 + 10)
                    let pill = CGRect(x: min(plotWidth - pillW - 4, p2.x + 8), y: max(topPadding + 4, p2.y - 18), width: pillW, height: 16)
                    ctx.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(t.cardBg.opacity(0.92)))
                    ctx.stroke(Path(roundedRect: pill, cornerRadius: 4), with: .color(col.opacity(0.65)), lineWidth: 0.8)
                    ctx.draw(Text(readout).font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(t.primaryText), at: CGPoint(x: pill.midX, y: pill.midY))
                }
            }
        case .horizontalLine:
            var path = Path(); path.move(to: CGPoint(x: 0, y: p1.y)); path.addLine(to: CGPoint(x: plotWidth, y: p1.y))
            ctx.stroke(path, with: .color(col), style: strokeStyle)
            ctx.draw(Text(store.instrument.formatPrice(obj.start.price)).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(col), at: CGPoint(x: plotWidth - 36, y: p1.y - 8))
        case .horizontalRay:
            var path = Path(); path.move(to: p1); path.addLine(to: CGPoint(x: plotWidth, y: p1.y))
            ctx.stroke(path, with: .color(col), style: strokeStyle)
        case .verticalLine:
            var path = Path(); path.move(to: CGPoint(x: p1.x, y: topPadding)); path.addLine(to: CGPoint(x: p1.x, y: topPadding + plotHeight))
            ctx.stroke(path, with: .color(col), style: strokeStyle)
        case .parallelChannel:
            let off: CGFloat = 34
            var fill = Path()
            fill.move(to: CGPoint(x: p1.x, y: p1.y - off)); fill.addLine(to: CGPoint(x: p2.x, y: p2.y - off))
            fill.addLine(to: CGPoint(x: p2.x, y: p2.y + off)); fill.addLine(to: CGPoint(x: p1.x, y: p1.y + off)); fill.closeSubpath()
            ctx.fill(fill, with: .color(col.opacity(0.14)))
            ctx.stroke(fill, with: .color(col), lineWidth: isSelected ? 1.8 : 1.3)
        case .fibRetracement:
            let levels: [Double] = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0]
            let xMin = min(p1.x, p2.x)
            let xMax = max(p1.x, p2.x, xMin + 60)
            let delta = obj.end.price - obj.start.price
            for lvl in levels {
                let price = obj.end.price - delta * lvl
                let y = range.y(forPrice: price, topPadding: topPadding, plotHeight: plotHeight)
                var lp = Path(); lp.move(to: CGPoint(x: xMin, y: y)); lp.addLine(to: CGPoint(x: xMax, y: y))
                let isGolden = (lvl == 0.618 || lvl == 0.5)
                ctx.stroke(lp, with: .color(isGolden ? t.amber : col.opacity(0.8)), lineWidth: isGolden ? 1.5 : 1.0)
                ctx.draw(Text(String(format: "%.3f (%@)", lvl, store.instrument.formatPrice(price))).font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(isGolden ? t.amber : col), at: CGPoint(x: xMin + 54, y: y - 7))
            }
        case .rectangle:
            let rect = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: max(4, abs(p2.x - p1.x)), height: max(4, abs(p2.y - p1.y)))
            ctx.fill(Path(rect), with: .color(col.opacity(0.16)))
            ctx.stroke(Path(rect), with: .color(col), style: strokeStyle)
        case .longPosition, .shortPosition:
            let isLong = (obj.tool == .longPosition)
            let entry = obj.start.price
            let riskDist = max(abs(obj.end.price - entry), store.instrument.pipSize * 15)
            let slPrice = isLong ? (entry - riskDist) : (entry + riskDist)
            let tpPrice = isLong ? (entry + riskDist * obj.riskReward) : (entry - riskDist * obj.riskReward)
            let xStart = min(p1.x, p2.x); let width = max(72, abs(p2.x - p1.x))
            let yEntry = range.y(forPrice: entry, topPadding: topPadding, plotHeight: plotHeight)
            let ySL = range.y(forPrice: slPrice, topPadding: topPadding, plotHeight: plotHeight)
            let yTP = range.y(forPrice: tpPrice, topPadding: topPadding, plotHeight: plotHeight)
            let rewardRect = CGRect(x: xStart, y: min(yEntry, yTP), width: width, height: abs(yTP - yEntry))
            let riskRect = CGRect(x: xStart, y: min(yEntry, ySL), width: width, height: abs(ySL - yEntry))
            ctx.fill(Path(rewardRect), with: .color(t.bull.opacity(0.18)))
            ctx.stroke(Path(rewardRect), with: .color(t.bull.opacity(0.75)), lineWidth: 1)
            ctx.fill(Path(riskRect), with: .color(t.bear.opacity(0.18)))
            ctx.stroke(Path(riskRect), with: .color(t.bear.opacity(0.75)), lineWidth: 1)
            ctx.draw(Text(String(format: "%@ 1:%.1fR", isLong ? "LONG" : "SHORT", obj.riskReward)).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(t.primaryText), at: CGPoint(x: xStart + width * 0.5, y: yEntry - 7))
        case .priceRange:
            let rect = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: max(4, abs(p2.x - p1.x)), height: max(4, abs(p2.y - p1.y)))
            let diff = obj.end.price - obj.start.price
            let pips = diff / store.instrument.pipSize
            let pct = (diff / max(obj.start.price, 1e-6)) * 100.0
            let bars = abs(Int(round(obj.end.index - obj.start.index)))
            let tint = diff >= 0 ? t.bull : t.bear
            ctx.fill(Path(rect), with: .color(tint.opacity(0.15)))
            ctx.stroke(Path(rect), with: .color(tint), lineWidth: 1.1)
            let badge = CGRect(x: rect.midX - 92, y: rect.minY - 22, width: 184, height: 19)
            ctx.fill(Path(roundedRect: badge, cornerRadius: 5), with: .color(tint))
            ctx.draw(Text(String(format: "%+.1f pips (%.2f%%) • %d bars", pips, pct, bars)).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(.white), at: CGPoint(x: badge.midX, y: badge.midY))
        case .textNote:
            let pill = CGRect(x: p1.x, y: p1.y - 11, width: 96, height: 22)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 6), with: .color(col.opacity(0.22)))
            ctx.stroke(Path(roundedRect: pill, cornerRadius: 6), with: .color(col), lineWidth: 1.1)
            ctx.draw(Text(obj.label).font(.system(size: 10, weight: .bold)).foregroundStyle(t.primaryText), at: CGPoint(x: pill.midX, y: pill.midY))
        }

        // TradingView-style white/blue resize handles when selected!
        if isSelected {
            drawSelectionHandle(ctx: &ctx, at: p1, accent: t.accent)
            if !obj.tool.isSinglePoint {
                drawSelectionHandle(ctx: &ctx, at: p2, accent: t.accent)
            }
        }
    }

    private func drawSelectionHandle(ctx: inout GraphicsContext, at pt: CGPoint, accent: Color) {
        let r = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
        ctx.fill(Path(ellipseIn: r), with: .color(.white))
        ctx.stroke(Path(ellipseIn: r), with: .color(accent), lineWidth: 2.0)
    }

    // MARK: - On-Chart Overlays

    private func selectedDrawingToolbar(drawing: DrawingObject, theme t: AppTheme) -> some View {
        HStack(spacing: 10) {
            Text(drawing.tool.rawValue)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(t.primaryText)

            Divider().frame(height: 14).overlay(t.border)

            HStack(spacing: 5) {
                ForEach(DrawingColorPreset.presets) { preset in
                    Button {
                        store.setSelectedDrawingColor(preset.id)
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(t.primaryText, lineWidth: drawing.colorPresetId == preset.id ? 2 : 0).padding(-1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 14).overlay(t.border)

            Button {
                store.duplicateSelectedDrawing()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 12))
                    .foregroundStyle(t.primaryText)
            }
            .buttonStyle(.plain)
            .help("Duplicate drawing")

            Button {
                store.deleteSelectedDrawing()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(t.bear)
            }
            .buttonStyle(.plain)
            .help("Delete drawing (Delete)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(t.cardBg.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(t.isDark ? 0.35 : 0.10), radius: 8, y: 2)
    }

    @ViewBuilder
    private func ohlcHeader(candles: [Candle], range: VisibleRange, plotWidth: CGFloat, theme t: AppTheme) -> some View {
        let hovered: Candle? = {
            guard let pt = hoverLocation, pt.x >= 0, pt.x <= plotWidth else { return candles.last }
            let idx = Int(round(range.index(forX: pt.x)))
            return candles.indices.contains(idx) ? candles[idx] : candles.last
        }()

        if let c = hovered {
            HStack(spacing: 10) {
                Text("\(store.instrument.rawValue) · \(store.timeframe.rawValue)")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.primaryText)
                ohlcPill("O", store.instrument.formatPrice(c.open), t.primaryText, t.secondaryText)
                ohlcPill("H", store.instrument.formatPrice(c.high), t.primaryText, t.secondaryText)
                ohlcPill("L", store.instrument.formatPrice(c.low), t.primaryText, t.secondaryText)
                ohlcPill("C", store.instrument.formatPrice(c.close), c.isBullish ? t.bull : t.bear, t.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(t.cardBg.opacity(0.92), in: RoundedRectangle(cornerRadius: t.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: t.radiusControl).stroke(t.border, lineWidth: 0.75))
            .allowsHitTesting(false)
        }
    }

    private func ohlcPill(_ k: String, _ v: String, _ vc: Color, _ kc: Color) -> some View {
        HStack(spacing: 3) {
            Text(k).foregroundStyle(kc)
            Text(v).foregroundStyle(vc)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
    }

    @ViewBuilder
    private func activeStudiesLegend(theme t: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(store.activeStudies) { study in
                HStack(spacing: 8) {
                    Circle()
                        .fill(study.isVisible ? t.accent : t.border)
                        .frame(width: 5.5, height: 5.5)
                    Text(study.kind.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(study.isVisible ? t.primaryText : t.secondaryText)

                    HStack(spacing: 6) {
                        Button { store.toggleStudyVisibility(study.kind) } label: {
                            Image(systemName: study.isVisible ? "eye" : "eye.slash").font(.system(size: 10)).foregroundStyle(t.secondaryText)
                        }.buttonStyle(.plain).help(study.isVisible ? "Hide" : "Show")

                        Button { store.settingsStudyKind = study.kind } label: {
                            Image(systemName: "gearshape").font(.system(size: 10)).foregroundStyle(t.secondaryText)
                        }.buttonStyle(.plain).help("Settings")

                        Button { store.removeStudy(study.kind) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(t.secondaryText)
                        }.buttonStyle(.plain).help("Remove")
                    }
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 4)
                .background(t.cardBg.opacity(0.88), in: RoundedRectangle(cornerRadius: t.radiusSharp))
                .overlay(RoundedRectangle(cornerRadius: t.radiusSharp).stroke(t.border, lineWidth: 0.7))
            }

            Button {
                store.showIndicatorLibrary = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 10.5))
                    Text("Indicators (\(store.activeStudies.count)/\(StudyKind.allCases.count))")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(t.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(t.cardBg.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(t.accent.opacity(0.35), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
    }

    private func activeDrawingHint(theme t: AppTheme) -> some View {
        let hintText: String = {
            if store.activeTool.isSinglePoint {
                return "\(store.activeTool.rawValue): Click chart to place (Esc to cancel)"
            }
            if isAwaitingSecondPoint {
                return "\(store.activeTool.rawValue): Move & click Point 2 · Hold ⇧ for 0°/45° (Esc cancel)"
            }
            return "\(store.activeTool.rawValue): Click Point 1 & Point 2, or drag · Hold ⇧ to snap"
        }()
        return HStack(spacing: 8) {
            Image(systemName: store.activeTool.iconName).font(.system(size: 11, weight: .bold))
            Text(hintText)
                .font(.system(size: 11, weight: .semibold))
            Button("Done") {
                store.activeTool = .cursor
                draftDrawing = nil
                isAwaitingSecondPoint = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
        }
        .foregroundStyle(t.isDark ? .black : .white)
        .padding(.horizontal, 11)
        .padding(.vertical, 5.5)
        .background(t.accent, in: RoundedRectangle(cornerRadius: t.radiusControl))
    }

    private func sidewayDashboardCard(theme t: AppTheme) -> some View {
        let s = store.computed.sideway
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SIDEWAY & READINESS").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(t.secondaryText)
                Spacer()
                Text(s.cutoffWarning ? "UTC+7 Cutoff" : (s.inWorkingHoursUTC7 ? "UTC+7 Active" : "Off-Hours"))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(s.cutoffWarning ? t.amber : (s.inWorkingHoursUTC7 ? t.bull : t.secondaryText))
            }
            dashRow("ADX Cycle", s.regimeLabel, s.regimeLabel == "Strong Trend" ? t.bull : (s.regimeLabel == "Sideway / Flat" ? t.accent : t.amber), t)
            dashRow("HTF Bias", s.htfBias, s.htfBias == "Bullish" ? t.bull : (s.htfBias == "Bearish" ? t.bear : t.secondaryText), t)
            dashRow("ADX / ATR", String(format: "%.1f / %@", s.adxValue, store.instrument.formatPrice(store.computed.lastATR)), t.primaryText, t)
            dashRow("ADR Used", String(format: "%.0f%% %@", s.adrUsedPercent, s.adrDanger ? "(Danger)" : (s.adrGateOpen ? "(Open)" : "(Wait)")), s.adrDanger ? t.bear : (s.adrGateOpen ? t.bull : t.amber), t)
            dashRow("Scalp Zones", "\(s.activeScalpZones) active", s.activeScalpZones > 0 ? t.amber : t.secondaryText, t)
        }
        .padding(11)
        .frame(width: 224)
        .background(t.cardBg.opacity(0.92), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(t.border, lineWidth: 0.9))
        .shadow(color: .black.opacity(t.isDark ? 0.25 : 0.06), radius: 8, y: 2)
        .allowsHitTesting(false)
    }

    private func dashRow(_ label: String, _ value: String, _ tint: Color, _ t: AppTheme) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(t.secondaryText)
            Spacer()
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
    }
}
