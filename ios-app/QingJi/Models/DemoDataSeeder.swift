import Foundation
import SwiftData

/// 演示模式种子数据只在 `QINGJI_DEMO=1` 时运行，正式启动不会读取它。
///
/// 演示数据必须来自仓库里唯一的 canonical P0 fixture；如果 fixture 缺失
/// 或无法解码，直接让截图启动失败，不能悄悄回退到另一份硬编码数据。
enum DemoDataSeeder {
    static func seed(context: ModelContext) {
        do {
            let loaded = try P0ParityFixtureLoader.loadWithProvenance()
            try P0ParityDemoSeeder.seed(
                context: context,
                fixture: loaded.fixture,
                inputHash: loaded.inputHash
            )
        } catch {
            fatalError("P0 parity fixture cannot seed QingJi: \(error)")
        }
    }
}
