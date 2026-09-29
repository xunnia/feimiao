import SwiftUI

/// 账本封面：和安卓共用同一批肥喵封面图（assets/book_covers/*.png）。
/// 新建/编辑时存安卓同款路径 `assets/book_covers/<key>.png`，两端备份互通；
/// 老版本 iOS 存的短 key（daily/food/...）读取时自动映射，不用迁移数据。
enum BookCoverCatalog {
    /// 编辑页可选的封面，顺序与安卓 kBookTemplates 一致；default 是「日常生活」。
    static let choices = [
        "default", "dining", "shopping", "travel", "beauty", "business",
        "couple", "multi", "pet", "baby", "family"
    ]

    private static let known = Set(choices)
    private static let legacy: [String: String] = [
        "daily": "default",
        "food": "dining"
    ]

    /// 把存储值（安卓路径 / 老 iOS key / 空）解析成封面 key；认不出的回到 default。
    static func key(for stored: String) -> String {
        var value = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slash)...])
        }
        if value.hasSuffix(".png") {
            value = String(value.dropLast(4))
        }
        if let mapped = legacy[value] { return mapped }
        return known.contains(value) ? value : "default"
    }

    /// 写回数据库用安卓同款路径。
    static func storedValue(for key: String) -> String {
        "assets/book_covers/\(key).png"
    }

    static func imageName(for stored: String) -> String {
        "BookCover-\(key(for: stored))"
    }

    static func name(_ key: String) -> String {
        switch key {
        case "dining": return "餐饮"
        case "shopping": return "网购"
        case "travel": return "旅游"
        case "beauty": return "美妆"
        case "business": return "生意"
        case "couple": return "情侣"
        case "multi": return "多人"
        case "pet": return "宠物"
        case "baby": return "母婴"
        case "family": return "家庭"
        default: return "日常生活"
        }
    }
}

/// 竖版 46:54 圆角封面（安卓抽屉同比例）。`height` 决定大小，宽和圆角按比例算。
struct BookCoverView: View {
    let cover: String
    var height: CGFloat = 54

    var body: some View {
        Image(BookCoverCatalog.imageName(for: cover))
            .resizable()
            .scaledToFill()
            .frame(width: height * 46 / 54, height: height)
            .clipShape(.rect(cornerRadius: height * 10 / 54))
            .accessibilityLabel(BookCoverCatalog.name(BookCoverCatalog.key(for: cover)) + "封面")
    }
}
