import Foundation
import QingJiCore

/// 喵助手“记一记”消息的可持久化卡片状态。
///
/// 解析结果和真正写入的交易 ID 分开保存：解析卡可以跨重启恢复，整批撤销
/// 只会触碰这张卡实际创建的交易，不会误删用户后来手动记的账。
struct AIRecordCardState: Codable, Equatable, Sendable {
    var entries: [ParsedEntry]
    var categoryKeys: [String?]
    var transactionIDs: [UUID?]
    var deletedIndices: Set<Int>
    var saved: Bool
    var rolledBack: Bool
    var feedback: String

    init(
        entries: [ParsedEntry],
        categoryKeys: [String?] = [],
        transactionIDs: [UUID?] = [],
        deletedIndices: Set<Int> = [],
        saved: Bool = false,
        rolledBack: Bool = false,
        feedback: String = ""
    ) {
        self.entries = entries
        self.categoryKeys = categoryKeys
        self.transactionIDs = transactionIDs
        self.deletedIndices = deletedIndices
        self.saved = saved
        self.rolledBack = rolledBack
        self.feedback = feedback
    }

    func categoryKey(at index: Int) -> String? {
        index < categoryKeys.count ? categoryKeys[index] : nil
    }

    func transactionID(at index: Int) -> UUID? {
        index < transactionIDs.count ? transactionIDs[index] : nil
    }
}
