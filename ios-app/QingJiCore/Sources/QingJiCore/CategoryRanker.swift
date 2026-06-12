import Foundation

/// 分类智能排序：按使用频率 + 当前时段匹配度对分类排序，
/// 让「早上打开 App 时早餐分类排最前」。
public enum CategoryRanker {
    /// 把一天划分为 5 个消费时段：早(5-10)、午(10-14)、下午(14-17)、晚(17-21)、夜(21-5)。
    public static func timeBucket(forHour hour: Int) -> Int {
        switch hour {
        case 5..<10: return 0
        case 10..<14: return 1
        case 14..<17: return 2
        case 17..<21: return 3
        default: return 4
        }
    }

    /// 对 `defaultOrder` 中的分类重新排序，使用记录越多、与当前时段越匹配的越靠前。
    /// 得分相同的保持 `defaultOrder` 的相对顺序。
    public static func rank(
        defaultOrder: [String],
        usages: [(category: String, date: Date)],
        at referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let referenceBucket = timeBucket(forHour: calendar.component(.hour, from: referenceDate))
        var scores: [String: Double] = [:]
        for usage in usages {
            var score = 1.0
            if timeBucket(forHour: calendar.component(.hour, from: usage.date)) == referenceBucket {
                score += 2.0
            }
            if let days = calendar.dateComponents([.day], from: usage.date, to: referenceDate).day,
               days >= 0, days <= 30 {
                score += 0.5
            }
            scores[usage.category, default: 0] += score
        }

        let defaultIndex = Dictionary(
            defaultOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return defaultOrder.sorted { a, b in
            let scoreA = scores[a, default: 0]
            let scoreB = scores[b, default: 0]
            if scoreA != scoreB { return scoreA > scoreB }
            return defaultIndex[a, default: .max] < defaultIndex[b, default: .max]
        }
    }
}
