import Foundation
import SwiftData

/// 全局唯一的 ModelContainer，App、App Intents 共用。
/// 默认本地存储；在 Xcode 中为 App Target 开启 iCloud → CloudKit 能力后，
/// SwiftData 会自动启用同步（ModelConfiguration 默认 cloudKitDatabase: .automatic）。
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([Account.self, TxCategory.self, MoneyTransaction.self, Budget.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("无法创建数据库容器: \(error)")
        }
    }()
}
