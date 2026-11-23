import Foundation

struct BasketManagerConfig: Codable, Equatable {
    var enableBasketTP: Bool = true
    var tpMode: Int = 3 // 0=Money, 1=Pips, 2=ATR, 3=Percent
    var tpValue: Double = 2.0
    var autoCloseAtTP: Bool = true
    var enableBasketSL: Bool = true
    var slMode: Int = 3
    var slValue: Double = 1.0
    var autoCloseAtSL: Bool = true
    var enableGridEntries: Bool = false
    var gridStepPips: Double = 50.0
    var gridLotMultiplier: Double = 1.15
    var gridMaxLevels: Int = 3
    var gridMaxOrderLots: Double = 0.10
    var magicNumber: Int = 150501
    var manageManualTrades: Bool = true
    var atrPeriod: Int = 14
}

struct AdaptiveGridConfig: Codable, Equatable {
    var startingLots: Double = 0.01
    var layerMultiplier: Double = 1.5
    var maxLotCap: Double = 10.0
    var pipStep: Double = 150.0
    var pipStepMode: Int = 0 // 0=Fixed, 1=ATR, 2=ATR Percentile, 3=BB Width, 4=Range, 5=Hybrid
    var atrPeriod: Int = 14
    var atrMultiplier: Double = 1.5
    var bbPeriod: Int = 20
    var bbDeviation: Double = 2.0
    var enableBuy: Bool = true
    var enableSell: Bool = true
    var buyMagicNumber: Int = 1001
    var sellMagicNumber: Int = 1002
    var enableEquityProtection: Bool = false
    var stopLossDrawdownPct: Double = 20.0
    var enableSpreadFilter: Bool = true
    var maxSpreadPips: Double = 50.0
    var enableSessionFilter: Bool = true
    var closeAllOutsideSession: Bool = true
    var utcOffsetHours: Int = 7 // UTC+7
    var asiaSession: String = "06:30-14:00"
    var londonSession: String = "14:00-18:00"
    var newYorkSession: String = "19:00-23:00"
    var tradeAsia: Bool = true
    var tradeLondon: Bool = false
    var tradeNewYork: Bool = false
    var stochasticGateActive: Bool = false
    var stochKPeriod: Int = 14
    var stochDPeriod: Int = 3
    var stochUpper: Double = 80.0
    var stochLower: Double = 20.0
}

struct RuleCondition: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: String // blockPressure, blockTouch, rsi, adx, delta, atrRatio
    var compare: String // gt, gte, lt, lte
    var value: Double
    var lookback: Int = 1
}

struct FourStageStrategyConfig: Codable, Equatable {
    var presetName: String = "M5-Structure-Retest-2R"
    var instrument: String = "XAU/USD"
    var timeframe: String = "M5"
    var nearATR: Double = 0.5
    var confirmationBars: Int = 3
    var riskReward: Double = 2.0
    var riskPercent: Double = 1.0
    var partialTakeProfit: Bool = true
    var breakevenRR: Double = 1.0
    var expiryBars: Int = 20
    var trendRules: [RuleCondition] = [
        RuleCondition(kind: "adx", compare: "gt", value: 22, lookback: 1)
    ]
    var setupRules: [RuleCondition] = [
        RuleCondition(kind: "blockPressure", compare: "gt", value: 55, lookback: 1)
    ]
    var retestRules: [RuleCondition] = [
        RuleCondition(kind: "blockTouch", compare: "gte", value: 1, lookback: 1)
    ]
    var entryRules: [RuleCondition] = [
        RuleCondition(kind: "delta", compare: "gt", value: 800, lookback: 1),
        RuleCondition(kind: "rsi", compare: "lt", value: 70, lookback: 1)
    ]
}
