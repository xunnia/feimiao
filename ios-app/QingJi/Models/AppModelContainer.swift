import Foundation
import SwiftData

/// 全局唯一的 ModelContainer，App、App Intents 共用。
/// 默认本地存储；在 Xcode 中为 App Target 开启 iCloud → CloudKit 能力后，
/// SwiftData 会自动启用同步（ModelConfiguration 默认 cloudKitDatabase: .automatic）。
///
/// 当进程环境变量 QINGJI_DEMO == "1" 时，改用内存容器（isStoredInMemoryOnly: true）
/// 并灌入演示数据，用于 CI 截图。真实用户和打包的 IPA 不受影响。
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([Account.self, TxCategory.self, MoneyTransaction.self, Budget.self])
        do {
            // 演示模式：内存容器，CI 截图专用
            if ProcessInfo.processInfo.environment["QINGJI_DEMO"] == "1" {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: [config])
                DemoDataSeeder.seed(context: container.mainContext)
                return container
            }
            // 正常模式：本地持久化存储
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("无法创建数据库容器: \(error)")
        }
    }()
}
