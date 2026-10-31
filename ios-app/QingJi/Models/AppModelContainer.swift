import Foundation
import SwiftData

/// 全局唯一的 ModelContainer，App、App Intents 共用。
/// 默认本地存储；在 Xcode 中为 App Target 开启 iCloud → CloudKit 能力后，
/// SwiftData 会自动启用同步（ModelConfiguration 默认 cloudKitDatabase: .automatic）。
///
/// 当进程环境变量 QINGJI_DEMO == "1" 时，改用内存容器（isStoredInMemoryOnly: true）
/// 并灌入演示数据，用于 CI 截图。真实用户和打包的 IPA 不受影响。
@MainActor
enum AppModelContainer {
    /// Production and disk-migration tests use exactly the same schema/plan.
    /// Opening failures propagate; never delete, replace, or silently rebuild a
    /// user's store. An explicit URL is for isolated tests and disables CloudKit.
    static func makeContainer(
        at url: URL? = nil,
        inMemory: Bool = false,
        migrationPlan: any SchemaMigrationPlan.Type = FeimiaoMigrationPlan.self
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FeimiaoSchemaV3.self)
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: [config])
    }

    private static var cachedContainer: ModelContainer?

    /// Cache successes only. A failed open remains retryable and never falls
    /// back to an empty/in-memory database for a real user.
    static var shared: ModelContainer {
        get throws {
            if let cachedContainer { return cachedContainer }
            // 演示模式：内存容器，CI 截图专用
            if ProcessInfo.processInfo.environment["QINGJI_DEMO"] == "1" {
                let container = try makeContainer(inMemory: true)
                // 用独立 Context 写演示数据；内存库各 Context 共享同一存储，
                // 保存后主界面的 @Query 仍可读取，且不携带种子写入的待保存状态。
                DemoDataSeeder.seed(context: ModelContext(container))
                cachedContainer = container
                return container
            }
            // 正常模式：本地持久化存储
            let container = try makeContainer()
            cachedContainer = container
            return container
        }
    }
}
