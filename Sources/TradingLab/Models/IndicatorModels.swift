import Foundation

enum StudyKind: String, CaseIterable, Identifiable, Codable {
    case concept
    case orderFlow
    case reversalTargets
    case sessionToolkits
    case sidewayDetector
    case momentumOscillator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concept: return "Market Structure 2.0"
        case .orderFlow: return "Order Flow & Delta"
        case .reversalTargets: return "Reversal & ATR Targets"
        case .sessionToolkits: return "Session Toolkits"
        case .sidewayDetector: return "Sideway Detector"
        case .momentumOscillator: return "Momentum Oscillator"
        }
    }

    var subtitle: String {
        switch self {
        case .concept: return "Internal/Swing BOS & CHoCH+, OB pressure %, RSI divergences and volume profile"
        case .orderFlow: return "BuAx+/BeAx+ accelerators, wickless stars, protected levels, FVGs and volume zones"
        case .reversalTargets: return "Volatility envelope (13×2.718), BB/RSI (25/72) reversals, ATR targets & PDH/PDL"
        case .sessionToolkits: return "Session volume profile (70% VA), Camarilla/Fib P2–P5 pivots, ADR & killzone"
        case .sidewayDetector: return "Scalp zones (impulse→quiet→OB), ADX cycle (10/50/30), ADR gate & UTC+7 hours"
        case .momentumOscillator: return "WaveTrend (10,21), smart reversals, divergences, HA bias & ZVWAP · separate pane"
        }
    }

    var isIndependentPane: Bool {
        self == .momentumOscillator
    }
}

struct ActiveStudy: Identifiable, Codable, Equatable {
    var id: String { kind.rawValue }
    var kind: StudyKind
    var isVisible: Bool = true
}

enum OscillatorKind: String, CaseIterable, Identifiable, Codable {
    case waveTrend = "WaveTrend + ZVWAP"
    case rsi = "RSI (14)"

    var id: String { rawValue }
}

enum PivotKind: String, CaseIterable, Identifiable, Codable {
    case camarilla = "Camarilla"
    case fibonacci = "Fibonacci"

    var id: String { rawValue }
}

struct IndicatorConfig: Codable, Equatable {
    // 1. Market Structure 2.0 (Concept 2.0 clean-room spec)
    var conceptShowStructure: Bool = true
    var conceptShowOrderBlocks: Bool = true
    var conceptShowDivergences: Bool = true
    var conceptShowEMA20: Bool = true
    var conceptShowEMA50: Bool = true
    var conceptShowEMA200: Bool = false
    var conceptShowVolumeProfile: Bool = true
    var conceptSwingLookback: Int = 4         // Internal swing lookback
    var conceptMacroSwingLookback: Int = 15   // Macro swing lookback for CHoCH+
    var conceptOrderCount: Int = 4            // Max active unmitigated OBs per side
    var conceptProfileBins: Int = 40

    // 2. Order Flow & Delta (Sn1P3r Order Flow clean-room spec)
    var orderFlowShowFVG: Bool = true
    var orderFlowShowImpulse: Bool = true     // BuAx+/BuAx-/BeAx+/BeAx- Accelerators
    var orderFlowPlusOnly: Bool = false       // Only high-conviction + accelerators
    var orderFlowShowWicklessStars: Bool = true
    var orderFlowShowProtectedLevels: Bool = true
    var orderFlowShowVolumeZones: Bool = true
    var orderFlowRangeFactor: Double = 1.4
    var orderFlowDeltaFactor: Double = 1.4
    var orderFlowVolumeThreshold: Double = 1.8
    var orderFlowShowVolumeHistogram: Bool = true

    // 3. Reversal & ATR Targets (Premium 2.0 clean-room spec)
    var revShowVolatilityBand: Bool = true
    var revVolatilityLength: Int = 13
    var revVolatilityMultiplier: Double = 2.718
    var revShowBollinger: Bool = true
    var revBBLength: Int = 20
    var revBBMultiplier: Double = 2.0
    var revBBThreshold: Double = 0.0004
    var revRSILength: Int = 14
    var revRSILower: Double = 30.0
    var revRSIUpper: Double = 70.0
    var revATRStopMult: Double = 2.0
    var revTP1: Double = 1.0
    var revTP2: Double = 2.0
    var revTP3: Double = 3.0
    var revShowPrevHighLow: Bool = true
    var revShowSwingCHoCH: Bool = true
    var revSwingLength: Int = 20

    // 4. Session Toolkits (Toolkits clean-room spec)
    var toolkitPivotKind: PivotKind = .camarilla
    var toolkitValueAreaPercent: Double = 70.0
    var toolkitShowPivots: Bool = true
    var toolkitShowADR: Bool = true

    // 5. Sideway Detector (Sideway Detector clean-room spec)
    var sidewayShowScalpZones: Bool = true
    var sidewayScMove: Double = 1.8           // Big move >= 1.8x usual swing
    var sidewayScMoveBars: Int = 16           // Usual swing lookback
    var sidewayScSlowPct: Double = 60.0       // Quiet candles <= 60% of impulse
    var sidewayScQuietBars: Int = 3           // Quiet candles needed
    var sidewayScSharePct: Double = 55.0      // Order block directional share >= 55%
    var sidewayScNearATR: Double = 0.25       // Near block within 0.25x ATR
    var sidewayADXLength: Int = 10
    var sidewayADXPeak: Double = 50.0
    var sidewayADXFlat: Double = 30.0
    var sidewayADRGatePct: Double = 50.0
    var sidewayADRDangerPct: Double = 100.0
    var sidewayWorkStartHour: Int = 6
    var sidewayWorkEndHour: Int = 17
    var sidewayCutoffMins: Int = 30

    // 6. Momentum Oscillator (Sn1P3r Oscillator clean-room spec)
    var oscillatorMode: OscillatorKind = .waveTrend
    var wtChannelLength: Int = 10
    var wtAverageLength: Int = 21
    var wtOverbought: Double = 53.0
    var wtOversold: Double = -53.0
    var oscSmartOnly: Bool = true
    var oscShowDivergences: Bool = true
    var oscShowHABias: Bool = true
    var oscHALength: Int = 7
    var oscHASmoothing: Int = 10
    var oscShowZVWAP: Bool = true
    var oscZVWAPLength: Int = 20
    var oscZVWAPUpper: Double = 2.5
    var oscZVWAPExtreme: Double = 3.0
    var rsiLength: Int = 14
    var atrLength: Int = 14

    init() {}

    /// Backwards-compatible decoding so future indicator updates never reset your saved local settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IndicatorConfig()
        conceptShowStructure = try c.decodeIfPresent(Bool.self, forKey: .conceptShowStructure) ?? d.conceptShowStructure
        conceptShowOrderBlocks = try c.decodeIfPresent(Bool.self, forKey: .conceptShowOrderBlocks) ?? d.conceptShowOrderBlocks
        conceptShowDivergences = try c.decodeIfPresent(Bool.self, forKey: .conceptShowDivergences) ?? d.conceptShowDivergences
        conceptShowEMA20 = try c.decodeIfPresent(Bool.self, forKey: .conceptShowEMA20) ?? d.conceptShowEMA20
        conceptShowEMA50 = try c.decodeIfPresent(Bool.self, forKey: .conceptShowEMA50) ?? d.conceptShowEMA50
        conceptShowEMA200 = try c.decodeIfPresent(Bool.self, forKey: .conceptShowEMA200) ?? d.conceptShowEMA200
        conceptShowVolumeProfile = try c.decodeIfPresent(Bool.self, forKey: .conceptShowVolumeProfile) ?? d.conceptShowVolumeProfile
        conceptSwingLookback = try c.decodeIfPresent(Int.self, forKey: .conceptSwingLookback) ?? d.conceptSwingLookback
        conceptMacroSwingLookback = try c.decodeIfPresent(Int.self, forKey: .conceptMacroSwingLookback) ?? d.conceptMacroSwingLookback
        conceptOrderCount = try c.decodeIfPresent(Int.self, forKey: .conceptOrderCount) ?? d.conceptOrderCount
        conceptProfileBins = try c.decodeIfPresent(Int.self, forKey: .conceptProfileBins) ?? d.conceptProfileBins

        orderFlowShowFVG = try c.decodeIfPresent(Bool.self, forKey: .orderFlowShowFVG) ?? d.orderFlowShowFVG
        orderFlowShowImpulse = try c.decodeIfPresent(Bool.self, forKey: .orderFlowShowImpulse) ?? d.orderFlowShowImpulse
        orderFlowPlusOnly = try c.decodeIfPresent(Bool.self, forKey: .orderFlowPlusOnly) ?? d.orderFlowPlusOnly
        orderFlowShowWicklessStars = try c.decodeIfPresent(Bool.self, forKey: .orderFlowShowWicklessStars) ?? d.orderFlowShowWicklessStars
        orderFlowShowProtectedLevels = try c.decodeIfPresent(Bool.self, forKey: .orderFlowShowProtectedLevels) ?? d.orderFlowShowProtectedLevels
        orderFlowShowVolumeZones = try c.decodeIfPresent(Bool.self, forKey: .orderFlowShowVolumeZones) ?? d.orderFlowShowVolumeZones
        orderFlowRangeFactor = try c.decodeIfPresent(Double.self, forKey: .orderFlowRangeFactor) ?? d.orderFlowRangeFactor
        orderFlowDeltaFactor = try c.decodeIfPresent(Double.self, forKey: .orderFlowDeltaFactor) ?? d.orderFlowDeltaFactor
        orderFlowVolumeThreshold = try c.decodeIfPresent(Double.self, forKey: .orderFlowVolumeThreshold) ?? d.orderFlowVolumeThreshold
        orderFlowShowVolumeHistogram = try c.decodeIfPresent(Bool.self, forKey: .orderFlowShowVolumeHistogram) ?? d.orderFlowShowVolumeHistogram

        revShowVolatilityBand = try c.decodeIfPresent(Bool.self, forKey: .revShowVolatilityBand) ?? d.revShowVolatilityBand
        revVolatilityLength = try c.decodeIfPresent(Int.self, forKey: .revVolatilityLength) ?? d.revVolatilityLength
        revVolatilityMultiplier = try c.decodeIfPresent(Double.self, forKey: .revVolatilityMultiplier) ?? d.revVolatilityMultiplier
        revShowBollinger = try c.decodeIfPresent(Bool.self, forKey: .revShowBollinger) ?? d.revShowBollinger
        revBBLength = try c.decodeIfPresent(Int.self, forKey: .revBBLength) ?? d.revBBLength
        revBBMultiplier = try c.decodeIfPresent(Double.self, forKey: .revBBMultiplier) ?? d.revBBMultiplier
        revBBThreshold = try c.decodeIfPresent(Double.self, forKey: .revBBThreshold) ?? d.revBBThreshold
        revRSILength = try c.decodeIfPresent(Int.self, forKey: .revRSILength) ?? d.revRSILength
        revRSILower = try c.decodeIfPresent(Double.self, forKey: .revRSILower) ?? d.revRSILower
        revRSIUpper = try c.decodeIfPresent(Double.self, forKey: .revRSIUpper) ?? d.revRSIUpper
        revATRStopMult = try c.decodeIfPresent(Double.self, forKey: .revATRStopMult) ?? d.revATRStopMult
        revTP1 = try c.decodeIfPresent(Double.self, forKey: .revTP1) ?? d.revTP1
        revTP2 = try c.decodeIfPresent(Double.self, forKey: .revTP2) ?? d.revTP2
        revTP3 = try c.decodeIfPresent(Double.self, forKey: .revTP3) ?? d.revTP3
        revShowPrevHighLow = try c.decodeIfPresent(Bool.self, forKey: .revShowPrevHighLow) ?? d.revShowPrevHighLow
        revShowSwingCHoCH = try c.decodeIfPresent(Bool.self, forKey: .revShowSwingCHoCH) ?? d.revShowSwingCHoCH
        revSwingLength = try c.decodeIfPresent(Int.self, forKey: .revSwingLength) ?? d.revSwingLength

        toolkitPivotKind = try c.decodeIfPresent(PivotKind.self, forKey: .toolkitPivotKind) ?? d.toolkitPivotKind
        toolkitValueAreaPercent = try c.decodeIfPresent(Double.self, forKey: .toolkitValueAreaPercent) ?? d.toolkitValueAreaPercent
        toolkitShowPivots = try c.decodeIfPresent(Bool.self, forKey: .toolkitShowPivots) ?? d.toolkitShowPivots
        toolkitShowADR = try c.decodeIfPresent(Bool.self, forKey: .toolkitShowADR) ?? d.toolkitShowADR

        sidewayShowScalpZones = try c.decodeIfPresent(Bool.self, forKey: .sidewayShowScalpZones) ?? d.sidewayShowScalpZones
        sidewayScMove = try c.decodeIfPresent(Double.self, forKey: .sidewayScMove) ?? d.sidewayScMove
        sidewayScMoveBars = try c.decodeIfPresent(Int.self, forKey: .sidewayScMoveBars) ?? d.sidewayScMoveBars
        sidewayScSlowPct = try c.decodeIfPresent(Double.self, forKey: .sidewayScSlowPct) ?? d.sidewayScSlowPct
        sidewayScQuietBars = try c.decodeIfPresent(Int.self, forKey: .sidewayScQuietBars) ?? d.sidewayScQuietBars
        sidewayScSharePct = try c.decodeIfPresent(Double.self, forKey: .sidewayScSharePct) ?? d.sidewayScSharePct
        sidewayScNearATR = try c.decodeIfPresent(Double.self, forKey: .sidewayScNearATR) ?? d.sidewayScNearATR
        sidewayADXLength = try c.decodeIfPresent(Int.self, forKey: .sidewayADXLength) ?? d.sidewayADXLength
        sidewayADXPeak = try c.decodeIfPresent(Double.self, forKey: .sidewayADXPeak) ?? d.sidewayADXPeak
        sidewayADXFlat = try c.decodeIfPresent(Double.self, forKey: .sidewayADXFlat) ?? d.sidewayADXFlat
        sidewayADRGatePct = try c.decodeIfPresent(Double.self, forKey: .sidewayADRGatePct) ?? d.sidewayADRGatePct
        sidewayADRDangerPct = try c.decodeIfPresent(Double.self, forKey: .sidewayADRDangerPct) ?? d.sidewayADRDangerPct
        sidewayWorkStartHour = try c.decodeIfPresent(Int.self, forKey: .sidewayWorkStartHour) ?? d.sidewayWorkStartHour
        sidewayWorkEndHour = try c.decodeIfPresent(Int.self, forKey: .sidewayWorkEndHour) ?? d.sidewayWorkEndHour
        sidewayCutoffMins = try c.decodeIfPresent(Int.self, forKey: .sidewayCutoffMins) ?? d.sidewayCutoffMins

        oscillatorMode = try c.decodeIfPresent(OscillatorKind.self, forKey: .oscillatorMode) ?? d.oscillatorMode
        wtChannelLength = try c.decodeIfPresent(Int.self, forKey: .wtChannelLength) ?? d.wtChannelLength
        wtAverageLength = try c.decodeIfPresent(Int.self, forKey: .wtAverageLength) ?? d.wtAverageLength
        wtOverbought = try c.decodeIfPresent(Double.self, forKey: .wtOverbought) ?? d.wtOverbought
        wtOversold = try c.decodeIfPresent(Double.self, forKey: .wtOversold) ?? d.wtOversold
        oscSmartOnly = try c.decodeIfPresent(Bool.self, forKey: .oscSmartOnly) ?? d.oscSmartOnly
        oscShowDivergences = try c.decodeIfPresent(Bool.self, forKey: .oscShowDivergences) ?? d.oscShowDivergences
        oscShowHABias = try c.decodeIfPresent(Bool.self, forKey: .oscShowHABias) ?? d.oscShowHABias
        oscHALength = try c.decodeIfPresent(Int.self, forKey: .oscHALength) ?? d.oscHALength
        oscHASmoothing = try c.decodeIfPresent(Int.self, forKey: .oscHASmoothing) ?? d.oscHASmoothing
        oscShowZVWAP = try c.decodeIfPresent(Bool.self, forKey: .oscShowZVWAP) ?? d.oscShowZVWAP
        oscZVWAPLength = try c.decodeIfPresent(Int.self, forKey: .oscZVWAPLength) ?? d.oscZVWAPLength
        oscZVWAPUpper = try c.decodeIfPresent(Double.self, forKey: .oscZVWAPUpper) ?? d.oscZVWAPUpper
        oscZVWAPExtreme = try c.decodeIfPresent(Double.self, forKey: .oscZVWAPExtreme) ?? d.oscZVWAPExtreme
        rsiLength = try c.decodeIfPresent(Int.self, forKey: .rsiLength) ?? d.rsiLength
        atrLength = try c.decodeIfPresent(Int.self, forKey: .atrLength) ?? d.atrLength
    }
}

struct PriceAlert: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var instrument: String
    var studyTitle: String
    var isAbove: Bool
    var targetPrice: Double
    var note: String
    var isTriggered: Bool = false
    var createdAt: Date = Date()
}

struct OrderBlockZone: Identifiable {
    let id: Int
    let startIndex: Int
    let endIndex: Int
    let top: Double
    let bottom: Double
    let isBullish: Bool
    let mitigated: Bool
    let pressurePercent: Double
    let isSwing: Bool
}

struct FairValueGap: Identifiable {
    let id: Int
    let startIndex: Int
    let top: Double
    let bottom: Double
    let isBullish: Bool
    let filled: Bool
}

struct StructureBreak: Identifiable {
    let id: Int
    let index: Int
    let fromIndex: Int
    let price: Double
    let label: String           // "BOS", "CHoCH", "CHoCH+"
    let isBullish: Bool
    let isMacro: Bool
}

struct RSIDivergence: Identifiable {
    let id: Int
    let startIndex: Int
    let endIndex: Int
    let startPrice: Double
    let endPrice: Double
    let isBullish: Bool
    let label: String           // "Bull Div" / "Bear Div"
}

struct AcceleratorMarker: Identifiable {
    let id: Int
    let index: Int
    let isBullish: Bool
    let isPlus: Bool            // true => BuAx+ / BeAx+, false => BuAx- / BeAx-
    let isWickless: Bool
    let deltaRatio: Double

    var caption: String {
        let prefix = isBullish ? "BuAx" : "BeAx"
        return prefix + (isPlus ? "+" : "-")
    }
}

struct ProtectedLevel: Identifiable {
    let id: Int
    let startIndex: Int
    let price: Double
    let isHigh: Bool
}

struct VolumeZone: Identifiable {
    let id: Int
    let startIndex: Int
    let top: Double
    let bottom: Double
    let isBullish: Bool
    let volumeMultiple: Double
}

struct ScalpZoneBox: Identifiable {
    let id: Int
    let startIndex: Int
    let endIndex: Int
    let top: Double
    let bottom: Double
    let isBullish: Bool
    let pressurePercent: Double
    let quietCount: Int
}

struct ReversalSetupSignal: Identifiable {
    let id: Int
    let index: Int
    let isBullish: Bool
    let entry: Double
    let stopLoss: Double
    let tp1: Double
    let tp2: Double
    let tp3: Double
}

struct VolumeProfileBin {
    let low: Double
    let high: Double
    let buyVolume: Double
    let sellVolume: Double
    var totalVolume: Double { buyVolume + sellVolume }
}

struct VolumeProfileResult {
    let bins: [VolumeProfileBin]
    let pocPrice: Double
    let vahPrice: Double
    let valPrice: Double
    let maxVolume: Double
}

struct PivotLevels {
    let kind: PivotKind
    let pivot: Double
    let r1: Double
    let r2: Double
    let r3: Double
    let r4: Double
    let r5: Double
    let s1: Double
    let s2: Double
    let s3: Double
    let s4: Double
    let s5: Double
}

struct WaveTrendPoint {
    let wt1: Double
    let wt2: Double
    let histogram: Double
    let buySignal: Bool
    let sellSignal: Bool
}

struct OscillatorDivergence: Identifiable {
    let id: Int
    let startIndex: Int
    let endIndex: Int
    let startWT: Double
    let endWT: Double
    let isBullish: Bool
}

struct SidewayStatus {
    let adxValue: Double
    let regimeLabel: String     // "Strong Trend", "Compressing", "Sideway / Flat", "Balanced"
    let htfBias: String         // "Bullish", "Bearish", "Neutral"
    let adrUsedPercent: Double
    let adrGateOpen: Bool
    let adrDanger: Bool
    let inWorkingHoursUTC7: Bool
    let cutoffWarning: Bool
    let activeScalpZones: Int
    let prevSessionHigh: Double?
    let prevSessionLow: Double?
}

struct ComputedIndicators {
    var ema20: [Double?] = []
    var ema50: [Double?] = []
    var ema200: [Double?] = []
    var bbUpper: [Double?] = []
    var bbMiddle: [Double?] = []
    var bbLower: [Double?] = []
    var volatilityUpper: [Double?] = []
    var volatilityLower: [Double?] = []
    var volatilityTrend: [Int] = []     // 1 = bullish support active, -1 = bearish resistance active
    var rsi: [Double?] = []
    var atr: [Double?] = []
    var adx: [Double?] = []
    var waveTrend: [WaveTrendPoint?] = []
    var oscDivergences: [OscillatorDivergence] = []
    var zvwap: [Double?] = []
    var haBiasBullish: [Bool?] = []
    var orderBlocks: [OrderBlockZone] = []
    var fvgs: [FairValueGap] = []
    var structureBreaks: [StructureBreak] = []
    var rsiDivergences: [RSIDivergence] = []
    var accelerators: [AcceleratorMarker] = []
    var protectedLevels: [ProtectedLevel] = []
    var volumeZones: [VolumeZone] = []
    var scalpZones: [ScalpZoneBox] = []
    var reversalSignals: [ReversalSetupSignal] = []
    var pivots: PivotLevels? = nil
    var sideway = SidewayStatus(
        adxValue: 0,
        regimeLabel: "Balanced",
        htfBias: "Neutral",
        adrUsedPercent: 0,
        adrGateOpen: false,
        adrDanger: false,
        inWorkingHoursUTC7: true,
        cutoffWarning: false,
        activeScalpZones: 0,
        prevSessionHigh: nil,
        prevSessionLow: nil
    )
    var lastATR: Double = 0
    var lastADX: Double = 0
    var lastRSI: Double = 50
    var lastZVWAP: Double = 0
    var marketRegime: String = "Balanced"
}
