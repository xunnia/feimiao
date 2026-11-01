import SwiftData

/// Leaf entities have no object relationships into the frozen ledger cluster.
/// Any future stored-property change to a leaf must first freeze that leaf in
/// the historical schemas too; changing this list is a schema migration.
private enum UnchangedAppModels {
    static var leafModels: [any PersistentModel.Type] { [
        Tag.self, Budget.self, SavingsGoal.self, RecurringRule.self,
        RecurringOccurrence.self, AssetEvent.self,
        AssetUsageEvent.self, AssetTransactionLink.self, AssetRefundAllocation.self,
        AssetValuation.self, ReceivableRecovery.self,
        LiabilityProfile.self, NetWorthSnapshot.self, AIChatSession.self,
        AIChatMessage.self, AIMemoryRecord.self, AIRequestRunRecord.self,
        AIRequestEventRecord.self, AIReportScheduleRecord.self, BudgetPlanRecord.self,
        BudgetPlanRevisionRecord.self, BudgetCycleOverrideRecord.self,
        BudgetCommitmentOccurrenceRecord.self, BudgetChangeEventRecord.self,
        ReportRecord.self, AccountBalanceCheckpointRecord.self,
        NetWorthVerifiedCheckpointRecord.self,
    ] }

    static var legacyLedger: [any PersistentModel.Type] { [
        LegacyLedgerModels.Account.self, LegacyLedgerModels.Book.self,
        LegacyLedgerModels.TxCategory.self, LegacyLedgerModels.MoneyTransaction.self,
    ] }

    /// Frozen leaves whose soft-delete flag is still stored as isDeleted.
    static var legacyAssets: [any PersistentModel.Type] { [
        LegacyAssetModels.PhysicalAsset.self, LegacyAssetModels.ReceivableAsset.self,
    ] }
}

/// The unversioned published graph at b40316f, before budget rule tables.
enum FeimiaoSchemaV1: VersionedSchema {
    static var sourceRevision: String { "b40316f336fb0aefabf67817460775b665fdaa1d" }
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        UnchangedAppModels.legacyLedger + UnchangedAppModels.legacyAssets + UnchangedAppModels.leafModels
    }
}

/// The most recent single-book graph, including the budget rule tables.
enum FeimiaoSchemaV2: VersionedSchema {
    static var sourceRevision: String { "9c0323cfa772107559c4edb5634122088aa82bc8" }
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        FeimiaoSchemaV1.models + [BudgetRuleRecord.self, BudgetRolloverChangeRecord.self]
    }
}

/// Only two defaulted attributes are added to MoneyTransaction, and the
/// soft-delete flag of Account, PhysicalAsset and ReceivableAsset is renamed to
/// isSoftDeleted (originalName "isDeleted" carries the value over; the old name
/// clashes with NSManagedObject.isDeleted). Old book
/// and account relationships remain intact; legacy scene fallback remains lazy.
enum FeimiaoSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Account.self,
            Book.self,
            TxCategory.self,
            Tag.self,
            MoneyTransaction.self,
            Budget.self,
            SavingsGoal.self,
            RecurringRule.self,
            RecurringOccurrence.self,
            PhysicalAsset.self,
            AssetEvent.self,
            AssetUsageEvent.self,
            AssetTransactionLink.self,
            AssetRefundAllocation.self,
            AssetValuation.self,
            ReceivableAsset.self,
            ReceivableRecovery.self,
            LiabilityProfile.self,
            NetWorthSnapshot.self,
            AIChatSession.self,
            AIChatMessage.self,
            AIMemoryRecord.self,
            AIRequestRunRecord.self,
            AIRequestEventRecord.self,
            AIReportScheduleRecord.self,
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetCycleOverrideRecord.self,
            BudgetCommitmentOccurrenceRecord.self,
            BudgetChangeEventRecord.self,
            BudgetRuleRecord.self,
            BudgetRolloverChangeRecord.self,
            ReportRecord.self,
            AccountBalanceCheckpointRecord.self,
            NetWorthVerifiedCheckpointRecord.self,
        ]
    }
}

enum FeimiaoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FeimiaoSchemaV1.self, FeimiaoSchemaV2.self, FeimiaoSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: FeimiaoSchemaV1.self, toVersion: FeimiaoSchemaV2.self),
         .lightweight(fromVersion: FeimiaoSchemaV2.self, toVersion: FeimiaoSchemaV3.self)]
    }
}
