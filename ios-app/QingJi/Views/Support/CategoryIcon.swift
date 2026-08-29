import SwiftUI
import UIKit

/// 与 Android 共用的分类图标风格。
///
/// Android 有面性和线性两套 `cat_icons_*` 资源；iOS 使用同一批资源，
/// 只把载体换成 UIImage，以保证分类 key、颜色、圆角方块和图形完全一致。
enum CategoryIconStyle: String, CaseIterable, Identifiable {
    case filled
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filled: "面性"
        case .line: "线性"
        }
    }

    var resourceDirectory: String { "CategoryIcons/\(rawValue)" }
}

/// Android `CatIcon` 的 iOS 实现。
///
/// 生产分类优先使用跨平台 PNG；用户自建分类或未来新增 key 没有资源时，
/// 回退到该分类保存的彩色 emoji，行为与 Android 一致，不显示空白占位。
struct CategoryIcon: View {
    let categoryKey: String
    let emoji: String
    var size: CGFloat = 36
    var style: CategoryIconStyle?

    @AppStorage("qingji.categoryIconStyle") private var storedStyleRaw = CategoryIconStyle.filled.rawValue

    init(
        categoryKey: String,
        emoji: String,
        size: CGFloat = 36,
        style: CategoryIconStyle? = nil
    ) {
        self.categoryKey = categoryKey
        self.emoji = emoji
        self.size = size
        self.style = style
    }

    private var activeStyle: CategoryIconStyle {
        style ?? CategoryIconStyle(rawValue: storedStyleRaw) ?? .filled
    }

    var body: some View {
        Group {
            if let image = CategoryIconImage.image(for: categoryKey, style: activeStyle) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text(emoji)
                    .font(.system(size: size * 0.64))
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum CategoryIconImage {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for categoryKey: String, style: CategoryIconStyle) -> UIImage? {
        guard !categoryKey.isEmpty else { return nil }
        let cacheKey = "\(style.rawValue)/\(categoryKey)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let path = Bundle.main.path(
            forResource: categoryKey,
            ofType: "png",
            inDirectory: style.resourceDirectory
        ), let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
