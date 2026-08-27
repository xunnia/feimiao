import Foundation

public enum AssetMetricQuality: String, Codable, Equatable, Sendable {
    case exact
    case unavailable
    case conflict
}

public struct AssetMetricValue<Value>: Equatable where Value: Equatable {
    public let quality: AssetMetricQuality
    public let value: Value?
    public let reason: String

    public init(exact value: Value) {
        self.quality = .exact
        self.value = value
        self.reason = ""
    }

    public init(unavailable reason: String) {
        self.quality = .unavailable
        self.value = nil
        self.reason = reason
    }

    public init(conflict reason: String) {
        self.quality = .conflict
        self.value = nil
        self.reason = reason
    }

    public var isExact: Bool { quality == .exact }
}

public struct PhysicalAssetMetricInput: Equatable {
    public let netAcquisitionCost: Decimal
    public let additionalNetCost: Decimal
    public let currentNetValue: Decimal
    public let purchasedAt: Date?
    public let endedAt: Date?
    public let isEconomicallyOwned: Bool
    public let hasKnownValuation: Bool
    public let hasComparableCurrency: Bool
    public let usageTrackingEnabled: Bool
    public let usageCount: Int

    public init(
        netAcquisitionCost: Decimal,
        additionalNetCost: Decimal = .zero,
        currentNetValue: Decimal,
        purchasedAt: Date?,
        endedAt: Date?,
        isEconomicallyOwned: Bool,
        hasKnownValuation: Bool,
        hasComparableCurrency: Bool = true,
        usageTrackingEnabled: Bool = false,
        usageCount: Int = 0
    ) {
        self.netAcquisitionCost = netAcquisitionCost
        self.additionalNetCost = additionalNetCost
        self.currentNetValue = currentNetValue
        self.purchasedAt = purchasedAt
        self.endedAt = endedAt
        self.isEconomicallyOwned = isEconomicallyOwned
        self.hasKnownValuation = hasKnownValuation
        self.hasComparableCurrency = hasComparableCurrency
        self.usageTrackingEnabled = usageTrackingEnabled
        self.usageCount = usageCount
    }
}

public struct PhysicalAssetMetrics: Equatable {
    public let heldDays: AssetMetricValue<Int>
    public let cumulativeHoldingInvestment: AssetMetricValue<Decimal>
    public let dailyHoldingCost: AssetMetricValue<Decimal>
    public let perUseHoldingCost: AssetMetricValue<Decimal>
    public let valueRetentionRatio: AssetMetricValue<Decimal>
}

public struct AssetValuationPoint: Equatable, Sendable {
    public let value: Decimal
    public let effectiveAt: Date
    public let isTermination: Bool

    public init(value: Decimal, effectiveAt: Date, isTermination: Bool = false) {
        self.value = value
        self.effectiveAt = effectiveAt
        self.isTermination = isTermination
    }
}

public struct AssetValuationTrend: Equatable, Sendable {
    public let points: [AssetValuationPoint]
    public let ignoredFutureCount: Int
    public let ignoredAfterTerminationCount: Int

    public init(
        points: [AssetValuationPoint],
        ignoredFutureCount: Int,
        ignoredAfterTerminationCount: Int
    ) {
        self.points = points
        self.ignoredFutureCount = ignoredFutureCount
        self.ignoredAfterTerminationCount = ignoredAfterTerminationCount
    }
}

public enum AssetMetrics {
    public static func resolve(
        _ input: PhysicalAssetMetricInput,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> PhysicalAssetMetrics {
        let heldDays = heldDays(
            purchasedAt: input.purchasedAt,
            endedAt: input.isEconomicallyOwned ? nil : input.endedAt,
            asOf: asOf,
            calendar: calendar
        )

        let cumulative: AssetMetricValue<Decimal>
        if !input.hasComparableCurrency {
            cumulative = AssetMetricValue(unavailable: "币种暂不可折算")
        } else if input.netAcquisitionCost < .zero {
            cumulative = AssetMetricValue(conflict: "净购置成本不能为负")
        } else if input.additionalNetCost < .zero {
            cumulative = AssetMetricValue(conflict: "附加净支出不能为负")
        } else {
            cumulative = AssetMetricValue(exact: input.netAcquisitionCost + input.additionalNetCost)
        }

        let daily = divide(cumulative, by: heldDays)
        let perUse: AssetMetricValue<Decimal>
        if !input.usageTrackingEnabled {
            perUse = AssetMetricValue(unavailable: "未开启使用次数")
        } else if input.usageCount < 0 {
            perUse = AssetMetricValue(conflict: "使用次数不能为负")
        } else if input.usageCount == 0 {
            perUse = AssetMetricValue(unavailable: "尚无使用记录")
        } else {
            perUse = divide(cumulative, by: input.usageCount)
        }

        let retention: AssetMetricValue<Decimal>
        if !input.isEconomicallyOwned {
            retention = AssetMetricValue(unavailable: "物品已结束持有")
        } else if !input.hasComparableCurrency {
            retention = AssetMetricValue(unavailable: "币种暂不可折算")
        } else if !input.hasKnownValuation {
            retention = AssetMetricValue(unavailable: "当前估值未知")
        } else if input.netAcquisitionCost <= .zero {
            retention = AssetMetricValue(unavailable: "净购置成本需大于 0")
        } else if input.currentNetValue < .zero {
            retention = AssetMetricValue(conflict: "当前估值不能为负")
        } else {
            retention = AssetMetricValue(exact: roundedDivision(input.currentNetValue, input.netAcquisitionCost))
        }

        return PhysicalAssetMetrics(
            heldDays: heldDays,
            cumulativeHoldingInvestment: cumulative,
            dailyHoldingCost: daily,
            perUseHoldingCost: perUse,
            valueRetentionRatio: retention
        )
    }

    public static func valuationTrend(
        _ source: some Sequence<AssetValuationPoint>,
        asOf: Date = Date(),
        endedAt: Date? = nil
    ) -> AssetValuationTrend {
        var future = 0
        var afterTermination = 0
        var accepted: [AssetValuationPoint] = []
        for point in source {
            if point.effectiveAt > asOf {
                future += 1
                continue
            }
            if let endedAt, point.effectiveAt > endedAt, !point.isTermination {
                afterTermination += 1
                continue
            }
            accepted.append(point)
        }
        accepted.sort {
            if $0.effectiveAt != $1.effectiveAt { return $0.effectiveAt < $1.effectiveAt }
            return !$0.isTermination && $1.isTermination
        }
        return AssetValuationTrend(
            points: accepted,
            ignoredFutureCount: future,
            ignoredAfterTerminationCount: afterTermination
        )
    }

    private static func heldDays(
        purchasedAt: Date?,
        endedAt: Date?,
        asOf: Date,
        calendar: Calendar
    ) -> AssetMetricValue<Int> {
        guard let purchasedAt else {
            return AssetMetricValue(unavailable: "购买日期未知")
        }
        let start = calendar.startOfDay(for: purchasedAt)
        let end = calendar.startOfDay(for: endedAt ?? asOf)
        guard end >= start else {
            return AssetMetricValue(conflict: "结束日期早于购买日期")
        }
        return AssetMetricValue(exact: (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private static func divide(
        _ numerator: AssetMetricValue<Decimal>,
        by denominator: AssetMetricValue<Int>
    ) -> AssetMetricValue<Decimal> {
        guard numerator.isExact else { return AssetMetricValue(quality: numerator.quality, reason: numerator.reason) }
        guard denominator.isExact else { return AssetMetricValue(quality: denominator.quality, reason: denominator.reason) }
        guard let value = denominator.value, value > 0, let numeratorValue = numerator.value else {
            return AssetMetricValue(unavailable: "没有足够的日期数据")
        }
        return AssetMetricValue(exact: roundedDivision(numeratorValue, Decimal(value)))
    }

    private static func divide(
        _ numerator: AssetMetricValue<Decimal>,
        by denominator: Int
    ) -> AssetMetricValue<Decimal> {
        guard numerator.isExact else { return AssetMetricValue(quality: numerator.quality, reason: numerator.reason) }
        guard denominator > 0, let value = numerator.value else {
            return AssetMetricValue(unavailable: "尚无使用记录")
        }
        return AssetMetricValue(exact: roundedDivision(value, Decimal(denominator)))
    }

    private static func roundedDivision(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        var left = lhs
        var right = rhs
        var result = Decimal.zero
        NSDecimalDivide(&result, &left, &right, .plain)
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &result, 8, .plain)
        return rounded
    }
}

private extension AssetMetricValue {
    init(quality: AssetMetricQuality, reason: String) {
        self.quality = quality
        self.value = nil
        self.reason = reason
    }
}
