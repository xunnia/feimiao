import Foundation

enum StatisticsCardLayout {
    static let unconfigured = "__default__"
    static let defaultOrder = ["battery", "budget_ring", "ring", "daily", "ranking", "top5", "sources"]
    static let registeredOrder = defaultOrder + ["insights", "heatmap", "radar", "stacked"]
    static let titles = [
        "battery": "截至今日进度",
        "budget_ring": "预算使用",
        "ring": "支出构成",
        "daily": "趋势图",
        "ranking": "分类排行",
        "top5": "单笔支出排行",
        "sources": "消费来源",
        "insights": "喵的洞察",
        "heatmap": "消费热力图",
        "radar": "本月 vs 上月",
        "stacked": "近 12 月收支",
    ]
    static let monthOnly: Set<String> = ["battery", "budget_ring", "sources", "insights", "heatmap", "radar", "stacked"]

    static func visibleKeys(from raw: String) -> [String] {
        guard raw != unconfigured else { return defaultOrder }
        var seen = Set<String>()
        return raw.split(separator: ",").map(String.init).filter {
            titles[$0] != nil && seen.insert($0).inserted
        }
    }

    static func toggled(_ key: String, on: Bool, in raw: String) -> String {
        guard titles[key] != nil else { return raw }
        var keys = visibleKeys(from: raw)
        if on {
            if !keys.contains(key) { keys.append(key) }
        } else {
            keys.removeAll { $0 == key }
        }
        return keys.joined(separator: ",")
    }

    static func moved(in raw: String, from source: Int, to destination: Int) -> String {
        var keys = visibleKeys(from: raw)
        guard keys.indices.contains(source), (0...keys.count).contains(destination) else { return raw }
        let item = keys.remove(at: source)
        keys.insert(item, at: source < destination ? destination - 1 : destination)
        return keys.joined(separator: ",")
    }

    static func applicable(_ keys: [String], month: Bool) -> [String] {
        month ? keys : keys.filter { !monthOnly.contains($0) }
    }
}
