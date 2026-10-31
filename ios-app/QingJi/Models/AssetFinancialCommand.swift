import Foundation
import SwiftData

/// One save commits an economic operation. Failure cleanup is scoped to this
/// operation rather than rolling back other editors sharing the ModelContext.
/// SwiftData cannot undelete a persisted row by inserting it again, so commands
/// that delete declare `deleting: true`: earlier pending edits are committed
/// first (as autosave would), and a failed save rolls back to that point.
enum AssetFinancialCommand {
    typealias Save = (ModelContext) throws -> Void

    final class Changes {
        private let context: ModelContext
        private let allowsDelete: Bool
        private var cleanup: [() -> Void] = []
        private(set) var requiresRollback = false

        init(context: ModelContext, allowsDelete: Bool = false) {
            self.context = context
            self.allowsDelete = allowsDelete
        }

        func restoreOnFailure(_ action: @escaping () -> Void) {
            cleanup.append(action)
        }

        /// Capture only the field this command changes. Other pending edits in
        /// the same shared context must survive a failed save.
        func set<Model: AnyObject, Value>(
            _ model: Model, _ keyPath: ReferenceWritableKeyPath<Model, Value>, _ value: Value
        ) {
            let previous = model[keyPath: keyPath]
            cleanup.append { model[keyPath: keyPath] = previous }
            model[keyPath: keyPath] = value
        }

        func insert<T: PersistentModel>(_ model: T) {
            context.insert(model)
            cleanup.append { [context] in context.delete(model) }
        }

        /// Deleted rows come back only through rollback; see the type comment.
        func delete<T: PersistentModel>(_ model: T) {
            assert(allowsDelete, "Commands that delete must pass deleting: true at the outermost perform")
            context.delete(model)
            requiresRollback = true
        }

        fileprivate func undo() { cleanup.reversed().forEach { $0() } }
    }

    static func perform<T>(
        in context: ModelContext,
        save: Save = { try $0.save() },
        joining parent: Changes? = nil,
        deleting: Bool = false,
        _ operation: (Changes) throws -> T
    ) throws -> T {
        // Composite operations share one undo journal and one final save.
        if let parent { return try operation(parent) }
        if deleting, context.hasChanges { try context.save() }
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        let changes = Changes(context: context, allowsDelete: deleting)
        do {
            let result = try operation(changes)
            try save(context)
            return result
        } catch {
            changes.undo()
            if changes.requiresRollback { context.rollback() }
            throw error
        }
    }

    static func contains<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Bool {
        let name = String(describing: type)
        return context.container.schema.entities.contains { $0.name == name || $0.name.hasSuffix(".\(name)") }
    }

    static func metadata(_ values: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func metadata(of event: AssetEvent) -> [String: String] {
        guard let data = event.metadataJSON.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data),
              let values = result as? [String: String] else { return [:] }
        return values
    }

    static func nextSequence(for id: UUID, command: String, in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<AssetEvent>()).filter {
            $0.assetID == id && metadata(of: $0)["command"] == command
        }.count + 1
    }

    static func activeAnchors(for accountID: UUID, in context: ModelContext) throws -> [AccountBalanceCheckpointRecord] {
        guard contains(AccountBalanceCheckpointRecord.self, in: context) else { return [] }
        let items = try AccountCheckpointStore.checkpoints(for: accountID, in: context)
        let reversed = Set(items.filter { $0.eventKindRaw == "reversal" && $0.status == "active" }.compactMap(\.reversalOfID))
        return items.filter { $0.eventKindRaw == "anchor" && $0.status == "active" && !reversed.contains($0.stableID) }
    }

    static func allowsEvent(at date: Date, for account: Account, in context: ModelContext) throws -> Bool {
        if account.openingBalanceQuality == .exact, let opening = account.openingBalanceEffectiveAt,
           date < opening { return false }
        return try activeAnchors(for: account.stableID, in: context).allSatisfy { date > $0.effectiveAt }
    }

    static func allowsUndo(for accountIDs: [UUID], createdAt: Date, in context: ModelContext) throws -> Bool {
        for id in accountIDs {
            // The current checkpoint adapter uses delta-at-creation. It cannot
            // prove safe removal after a later anchor, including backdated anchors.
            if try activeAnchors(for: id, in: context).contains(where: { $0.createdAt >= createdAt }) { return false }
        }
        return true
    }
}
