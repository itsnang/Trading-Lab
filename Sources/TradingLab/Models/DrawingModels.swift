import SwiftUI

enum DrawingTool: String, CaseIterable, Identifiable {
    case cursor = "Crosshair"
    case trendLine = "Trend Line"
    case horizontalLine = "Horizontal Line"
    case horizontalRay = "Horizontal Ray"
    case verticalLine = "Vertical Line"
    case parallelChannel = "Parallel Channel"
    case fibRetracement = "Fib Retracement"
    case rectangle = "Zone / Order Block"
    case longPosition = "Long Position"
    case shortPosition = "Short Position"
    case priceRange = "Price Range"
    case textNote = "Price Note"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .cursor: return "plus"
        case .trendLine: return "line.diagonal"
        case .horizontalLine: return "minus"
        case .horizontalRay: return "arrow.right"
        case .verticalLine: return "line.horizontal.3.decrease"
        case .parallelChannel: return "equal"
        case .fibRetracement: return "list.number"
        case .rectangle: return "rectangle"
        case .longPosition: return "arrow.up.right.square"
        case .shortPosition: return "arrow.down.right.square"
        case .priceRange: return "ruler"
        case .textNote: return "text.bubble"
        }
    }

    var isSinglePoint: Bool {
        switch self {
        case .horizontalLine, .verticalLine, .textNote:
            return true
        default:
            return false
        }
    }
}

struct ChartPoint: Equatable, Hashable {
    var index: Double   // candle index (supports fractional/future coordinates)
    var price: Double
}

struct DrawingColorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color

    static let presets: [DrawingColorPreset] = [
        DrawingColorPreset(id: "cyan", name: "Cyan", color: Color(red: 0.22, green: 0.78, blue: 0.96)),
        DrawingColorPreset(id: "amber", name: "Amber", color: Color(red: 0.96, green: 0.72, blue: 0.20)),
        DrawingColorPreset(id: "emerald", name: "Emerald", color: Color(red: 0.16, green: 0.82, blue: 0.56)),
        DrawingColorPreset(id: "rose", name: "Rose", color: Color(red: 0.95, green: 0.34, blue: 0.44)),
        DrawingColorPreset(id: "violet", name: "Violet", color: Color(red: 0.67, green: 0.48, blue: 0.98)),
        DrawingColorPreset(id: "slate", name: "White", color: Color(white: 0.90))
    ]
}

struct DrawingObject: Identifiable, Equatable {
    let id: UUID
    let tool: DrawingTool
    var start: ChartPoint
    var end: ChartPoint
    var colorPresetId: String
    var label: String
    var riskReward: Double = 2.0

    var color: Color {
        DrawingColorPreset.presets.first(where: { $0.id == colorPresetId })?.color ?? .cyan
    }
}
