import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class AssetFinancialCommandTests: XCTestCase {
    private enum Failure: Swift.Error { case save }

    private final class Stack {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self, Book.self, TxCategory.self, MoneyTransaction.self,
                AccountBalanceCheckpointRecord.self, PhysicalAsset.self, AssetEvent.self,
                AssetValuation.self, AssetUsageEvent.self, AssetTransactionLink.self,
                AssetRefundAllocation.self, ReceivableAsset.self, ReceivableRecovery.self,
                LiabilityProfile.self
            ])
            container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ])
            context = ModelContext(container)
            context.autosaveEnabled = false
        }

        func transactions() throws -> [MoneyTransaction] {
            try context.fetch(FetchDescriptor<MoneyTransaction>())
        }

        func netWorth() throws -> Decimal {
            try NetWorthStore.current(in: context).netWorth
        }
    }

    private func recoveryFixture(_ stack: Stack, included: Bool = true) throws -> (ReceivableAsset, Account) {
        let account = Account(name: "现金", kind: .cash)
        account.initialBalance = 2_000
        let asset = ReceivableAsset(name: "押金", originalAmount: 1_000, kind: .rentalDeposit)
        asset.includeInNetWorth = included
        stack.context.insert(account)
        stack.context.insert(asset)
        try stack.context.save()
        return (asset, account)
    }

    private func repaymentFixture(
        _ stack: Stack, balance: Decimal = -1_000, principal: Decimal = 1_000,
        mode: LiabilityBalanceMode = .legacyHybrid
    ) throws -> (LiabilityProfile, Account, Account) {
        let cash = Account(name: "现金", kind: .cash)
        cash.initialBalance = 2_000
        let debt = Account(name: "借款", kind: .loan)
        debt.initialBalance = balance
        debt.balanceMode = mode
        let profile = LiabilityProfile(accountID: debt.stableID, kind: .personalBorrow,
                                       originalPrincipal: 1_000, currentPrincipal: principal)
        stack.context.insert(cash)
        stack.context.insert(debt)
        stack.context.insert(profile)
        try stack.context.save()
        return (profile, cash, debt)
    }

    private func repay(_ profile: LiabilityProfile, _ cash: Account, _ stack: Stack,
                       amount: Decimal = 200) throws -> (principal: Decimal, interest: Decimal) {
        try LiabilityStore.repay(profile, amount: amount, fromAccount: cash, book: nil,
                                 category: nil, in: stack.context)
    }

    private func updateOriginalPrincipal(_ profile: LiabilityProfile, to amount: Decimal,
                                         account: Account, in stack: Stack) throws {
        try LiabilityStore.update(
            profile, in: stack.context, kind: profile.kind,
            originalPrincipal: amount, currentPrincipal: profile.currentPrincipal,
            account: account, counterparty: profile.counterparty, annualRate: profile.annualRate,
            statementDay: profile.statementDay, paymentDay: profile.paymentDay,
            creditLimit: profile.creditLimit, startDate: profile.startDate, dueDate: profile.dueDate,
            note: profile.note
        )
    }

    func testRecoveryMovesMoneyWithoutOrdinaryIncomeAndSurvivesReload() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        let before = try stack.netWorth()
        let recovery = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
        let transaction = try XCTUnwrap(stack.transactions().first)
        XCTAssertEqual(transaction.stableID, recovery.transactionID)
        XCTAssertEqual(transaction.eventType, .receivableRecovery)
        XCTAssertTrue(transaction.isExcluded)
        XCTAssertEqual(LedgerStore.accountBalance(for: cash, transactions: try stack.transactions()), 2_200)
        XCTAssertEqual(asset.remainingAmount, 800)
        XCTAssertEqual(try stack.netWorth(), before)
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetch(FetchDescriptor<ReceivableAsset>()).first?.remainingAmount, 800)
        XCTAssertEqual(try reload.fetch(FetchDescriptor<ReceivableRecovery>()).first?.transactionID, transaction.stableID)
    }

    func testFullRecoveryUndoRestoresInclusionAndBothSides() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack, included: false)
        _ = try ReceivableStore.recover(asset, amount: 1_000, in: stack.context, account: cash)
        XCTAssertEqual(asset.lifecycle, .recovered)
        try ReceivableStore.undoLatestRecovery(asset, in: stack.context)
        XCTAssertEqual(asset.remainingAmount, 1_000)
        XCTAssertEqual(asset.lifecycle, .active)
        XCTAssertFalse(asset.includeInNetWorth)
        XCTAssertNil(asset.endedAt)
        XCTAssertTrue(try stack.transactions().isEmpty)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 0)
        XCTAssertEqual(LedgerStore.accountBalance(for: cash, transactions: try stack.transactions()), 2_000)
    }

    func testRecoveryRoundingAndNoAccountDoesNotInventTransaction() throws {
        let stack = try Stack()
        let (asset, _) = try recoveryFixture(stack)
        let recovery = try ReceivableStore.recover(asset, amount: Decimal(string: "200.005")!, in: stack.context)
        XCTAssertEqual(recovery.amount, Decimal(string: "200.01")!)
        XCTAssertNil(recovery.transactionID)
        XCTAssertTrue(try stack.transactions().isEmpty)
        try ReceivableStore.undoLatestRecovery(asset, in: stack.context)
        XCTAssertEqual(asset.remainingAmount, 1_000)
    }

    func testRecoveryRejectsInactiveWrongCurrencyAndForeignAccount() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        cash.currencyCode = "USD"
        XCTAssertThrowsError(try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash))
        cash.currencyCode = "CNY"
        cash.status = .archived
        XCTAssertThrowsError(try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash))
        let foreign = Account(name: "未保存账户", kind: .cash)
        XCTAssertThrowsError(try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: foreign))
        XCTAssertEqual(asset.remainingAmount, 1_000)
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testRecoveryFailureCleansOnlyThisOperationAndIsNotPersistedLater() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        cash.name = "保留未保存的账户编辑"
        XCTAssertThrowsError(try ReceivableStore.recover(
            asset, amount: 200, in: stack.context, account: cash, save: { _ in throw Failure.save }
        ))
        XCTAssertEqual(asset.remainingAmount, 1_000)
        XCTAssertEqual(asset.lifecycle, .active)
        XCTAssertEqual(cash.name, "保留未保存的账户编辑")
        try stack.context.save()
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<ReceivableRecovery>()), 0)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), 0)
        XCTAssertEqual(try reload.fetch(FetchDescriptor<ReceivableAsset>()).first?.remainingAmount, 1_000)
    }

    func testUndoRecoveryFailureKeepsRecoveryAndArrivalAfterLaterSave() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
        XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context, save: { _ in throw Failure.save }))
        XCTAssertEqual(asset.remainingAmount, 800)
        try stack.context.save()
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), 1)
    }

    func testLegacyRecoveryUndoDoesNotInventMoneyOrInclusionIntent() throws {
        let stack = try Stack()
        let (asset, _) = try recoveryFixture(stack, included: false)
        asset.remainingAmount = 800
        asset.lifecycle = .partiallyRecovered
        stack.context.insert(ReceivableRecovery(receivableID: asset.stableID, amount: 200))
        try stack.context.save()
        try ReceivableStore.undoLatestRecovery(asset, in: stack.context)
        XCTAssertEqual(asset.remainingAmount, 1_000)
        XCTAssertFalse(asset.includeInNetWorth)
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testBackdatedRecoveryUndoUsesLastCreatedOperation() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        let first = try ReceivableStore.recover(asset, amount: 100, in: stack.context, account: cash,
                                                date: Date(timeIntervalSince1970: 2_000))
        first.createdAt = Date(timeIntervalSince1970: 3_000)
        let second = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash,
                                                 date: Date(timeIntervalSince1970: 1_000))
        second.createdAt = Date(timeIntervalSince1970: 4_000)
        try stack.context.save()
        try ReceivableStore.undoLatestRecovery(asset, in: stack.context)
        XCTAssertEqual(asset.remainingAmount, 900)
        XCTAssertEqual(try stack.context.fetch(FetchDescriptor<ReceivableRecovery>()).first?.stableID, first.stableID)
    }

    func testLegacyHybridNonnegativeAndMismatchedDebtAreRejectedWithoutWriting() throws {
        for balance in [Decimal.zero, Decimal(200), Decimal(-800)] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack, balance: balance)
            let before = try stack.netWorth()
            XCTAssertThrowsError(try repay(profile, cash, stack))
            XCTAssertEqual(profile.currentPrincipal, 1_000)
            XCTAssertEqual(try stack.netWorth(), before)
            XCTAssertTrue(try stack.transactions().isEmpty)
        }
    }

    func testLegacyNegativeDebtRepaymentAndUndoConserveNetWorth() throws {
        let stack = try Stack()
        let (profile, cash, debt) = try repaymentFixture(stack)
        let before = try stack.netWorth()
        let result = try repay(profile, cash, stack)
        XCTAssertEqual(result.principal, 200)
        XCTAssertEqual(result.interest, 0)
        XCTAssertEqual(profile.currentPrincipal, 800)
        XCTAssertEqual(LedgerStore.accountBalance(for: debt, transactions: try stack.transactions()), -800)
        XCTAssertEqual(try stack.netWorth(), before)
        try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
        XCTAssertEqual(profile.currentPrincipal, 1_000)
        XCTAssertTrue(try stack.transactions().isEmpty)
        XCTAssertEqual(try stack.netWorth(), before)
    }

    func testLedgerModeUsesActualDebtInsteadOfStaleProfileToSplitInterest() throws {
        let stack = try Stack()
        let (profile, cash, debt) = try repaymentFixture(stack, balance: -1_000, principal: 100, mode: .ledger)
        let before = try stack.netWorth()
        let result = try repay(profile, cash, stack, amount: 300)
        XCTAssertEqual(result.principal, 300)
        XCTAssertEqual(result.interest, 0)
        XCTAssertEqual(profile.currentPrincipal, 0)
        XCTAssertEqual(profile.lifecycle, .active)
        XCTAssertEqual(LedgerStore.accountBalance(for: debt, transactions: try stack.transactions()), -700)
        XCTAssertEqual(try stack.netWorth(), before)
        XCTAssertEqual(try stack.transactions().count, 1)
    }

    func testActualExcessIsInterestAndPrincipalPlusInterestCannotBeDeletedIndependently() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 100)
        let before = try stack.netWorth()
        let result = try repay(profile, cash, stack, amount: 150)
        XCTAssertEqual(result.principal, 100)
        XCTAssertEqual(result.interest, 50)
        XCTAssertEqual(try stack.netWorth(), before - 50)
        for transaction in try stack.transactions() {
            XCTAssertThrowsError(try LedgerStore.delete(transaction, in: stack.context)) { error in
                XCTAssertEqual(error as? LedgerStore.Error, .assetOperationLinked)
            }
        }
        try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
        XCTAssertEqual(try stack.netWorth(), before)
    }

    func testZeroPrincipalCreditCardKeepsPureTransfer() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack, principal: 0)
        profile.kind = .creditCard
        let result = try repay(profile, cash, stack, amount: 300)
        XCTAssertEqual(result.principal, 300)
        XCTAssertEqual(result.interest, 0)
        XCTAssertEqual(profile.currentPrincipal, 0)
        XCTAssertEqual(try stack.transactions().first?.eventType, .transfer)
    }

    func testZeroOriginalAndCurrentPrincipalCreditCardTransferCanBeUndone() throws {
        for mode in [LiabilityBalanceMode.legacyHybrid, .ledger] {
            let stack = try Stack()
            let cash = Account(name: "现金", kind: .cash)
            cash.initialBalance = 2_000
            let debt = Account(name: "信用卡", kind: .creditCard)
            debt.initialBalance = -1_000
            debt.balanceMode = mode
            let profile = LiabilityProfile(
                accountID: debt.stableID, kind: .creditCard, originalPrincipal: 0, currentPrincipal: 0
            )
            stack.context.insert(cash)
            stack.context.insert(debt)
            stack.context.insert(profile)
            try stack.context.save()

            let result = try repay(profile, cash, stack, amount: 300)
            XCTAssertEqual(result.principal, 300)
            XCTAssertEqual(result.interest, 0)
            let rows = try stack.transactions()
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.eventType, .transfer)
            XCTAssertEqual(LedgerStore.accountBalance(for: cash, transactions: rows), 1_700)
            XCTAssertEqual(LedgerStore.accountBalance(for: debt, transactions: rows), -700)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            XCTAssertEqual(AssetFinancialCommand.metadata(of: event)["original_principal"], "0")

            try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
            let reload = ModelContext(stack.container)
            let saved = try XCTUnwrap(reload.fetch(FetchDescriptor<LiabilityProfile>()).first)
            XCTAssertEqual(saved.originalPrincipal, 0)
            XCTAssertEqual(saved.currentPrincipal, 0)
            XCTAssertEqual(saved.lifecycle, .active)
            XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
            let accounts = try reload.fetch(FetchDescriptor<Account>())
            let savedCash = try XCTUnwrap(accounts.first { $0.stableID == cash.stableID })
            let savedDebt = try XCTUnwrap(accounts.first { $0.stableID == debt.stableID })
            XCTAssertEqual(LedgerStore.accountBalance(for: savedCash, transactions: []), 2_000)
            XCTAssertEqual(LedgerStore.accountBalance(for: savedDebt, transactions: []), -1_000)
        }
    }

    func testRepaymentSaveFailureLeavesNoHalfOperationOrDeferredWrites() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 100)
        XCTAssertThrowsError(try LiabilityStore.repay(
            profile, amount: 150, fromAccount: cash, book: nil, category: nil,
            in: stack.context, save: { _ in throw Failure.save }
        ))
        XCTAssertEqual(profile.currentPrincipal, 100)
        XCTAssertEqual(profile.lifecycle, .active)
        try stack.context.save()
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), 0)
        XCTAssertEqual(try reload.fetch(FetchDescriptor<LiabilityProfile>()).first?.currentPrincipal, 100)
    }

    func testUndoRepaymentRejectsChangedProfileAndReversesLatestFirst() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack)
        _ = try repay(profile, cash, stack, amount: 100)
        _ = try repay(profile, cash, stack, amount: 200)
        profile.currentPrincipal = 650
        XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context))
        profile.currentPrincipal = 700
        try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
        XCTAssertEqual(profile.currentPrincipal, 900)
        try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
        XCTAssertEqual(profile.currentPrincipal, 1_000)
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testAssociatedPurchaseAndRecoveryCannotBeEditedFromOrdinaryLedger() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        _ = try ReceivableStore.recover(asset, amount: 100, in: stack.context, account: cash)
        let recoveryTransaction = try XCTUnwrap(stack.transactions().first)
        XCTAssertThrowsError(try LedgerStore.updateTransaction(
            recoveryTransaction, amount: 200, date: Date(), note: "改款", category: nil,
            account: cash, reimbursable: false, isExcluded: false, in: stack.context
        ))
        let ordinary = try LedgerStore.createTransaction(in: stack.context, amount: 10, kind: .expense,
                                                         date: Date(), account: cash)
        stack.context.insert(AssetTransactionLink(assetID: UUID(), transactionID: ordinary.stableID))
        try stack.context.save()
        XCTAssertThrowsError(try LedgerStore.delete(ordinary, in: stack.context))
        XCTAssertEqual(try stack.transactions().count, 2)
    }

    func testReturnFailureDoesNotCommitRefundBeforeAssetState() throws {
        let stack = try Stack()
        let (_, cash) = try recoveryFixture(stack)
        let asset = try AssetStore.createPurchased(in: stack.context, name: "相机", kind: .other,
                                                   purchasePrice: 1_000, currentValue: 900,
                                                   account: cash, purchaseDate: Date())
        let before = try stack.netWorth()
        let eventsBefore = try stack.context.fetchCount(FetchDescriptor<AssetEvent>())
        XCTAssertThrowsError(try AssetStore.returnToPurchase(asset, in: stack.context, save: { _ in throw Failure.save }))
        XCTAssertEqual(asset.lifecycle, .owned)
        XCTAssertEqual(asset.currentValue, 900)
        try stack.context.save()
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), eventsBefore)
        XCTAssertEqual(try stack.netWorth(), before)
    }

    func testUnlinkedAssetPurchaseBecomesEditableAgain() throws {
        let stack = try Stack()
        let (_, cash) = try recoveryFixture(stack)
        let asset = try AssetStore.createPurchased(in: stack.context, name: "相机", kind: .other,
            purchasePrice: 1_000, currentValue: 900, account: cash, purchaseDate: Date())
        let purchase = try XCTUnwrap(stack.transactions().first)
        XCTAssertEqual(purchase.eventType, .assetPurchase)
        XCTAssertThrowsError(try LedgerStore.updateTransaction(
            purchase, amount: 1_100, date: purchase.date, note: "修正购置金额", category: nil,
            account: cash, reimbursable: false, isExcluded: false, in: stack.context
        )) { error in
            XCTAssertEqual(error as? LedgerStore.Error, .assetOperationLinked)
        }
        let links = try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter { $0.assetID == asset.stableID && $0.transactionID == purchase.stableID }
        XCTAssertEqual(links.count, 1)
        links.forEach(stack.context.delete)
        stack.context.insert(AssetEvent(assetID: asset.stableID, kind: .transactionUnlinked))
        try stack.context.save()

        try LedgerStore.updateTransaction(purchase, amount: 1_100, date: purchase.date,
            note: "修正购置金额", category: nil, account: cash, reimbursable: false,
            isExcluded: false, in: stack.context)
        let reload = ModelContext(stack.container)
        let saved = try XCTUnwrap(reload.fetch(FetchDescriptor<MoneyTransaction>()).first)
        XCTAssertEqual(saved.amount, 1_100)
        XCTAssertEqual(saved.note, "修正购置金额")
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetTransactionLink>()), 0)
    }

    func testReturnRefundIsProtectedOnlyUntilReturnIsUndone() throws {
        let stack = try Stack()
        let (_, cash) = try recoveryFixture(stack)
        let asset = try AssetStore.createPurchased(in: stack.context, name: "相机", kind: .other,
            purchasePrice: 1_000, currentValue: 900, account: cash, purchaseDate: Date())
        let refund = try AssetStore.returnToPurchase(asset, in: stack.context)
        let refundID = refund.stableID
        XCTAssertEqual(asset.lifecycle, .returned)
        XCTAssertThrowsError(try LedgerStore.delete(refund, in: stack.context)) { error in
            XCTAssertEqual(error as? LedgerStore.Error, .assetOperationLinked)
        }
        try AssetStore.undoReturn(asset, in: stack.context)
        XCTAssertEqual(asset.lifecycle, .owned)
        XCTAssertTrue(try stack.transactions().contains { $0.stableID == refundID })
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>()), 1)

        try LedgerStore.delete(refund, in: stack.context)
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertFalse(try reload.fetch(FetchDescriptor<MoneyTransaction>())
            .contains { $0.stableID == refundID })
        XCTAssertTrue(try reload.fetch(FetchDescriptor<AssetEvent>()).contains {
            $0.assetID == asset.stableID && $0.kind == .returned
        })
    }

    func testUndoRepaymentSaveFailureRetainsMoneyAndProfileAfterLaterSave() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack)
        _ = try repay(profile, cash, stack, amount: 200)
        XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(
            profile, in: stack.context, save: { _ in throw Failure.save }
        ))
        XCTAssertEqual(profile.currentPrincipal, 800)
        try stack.context.save()
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), 1)
        XCTAssertEqual(try reload.fetch(FetchDescriptor<LiabilityProfile>()).first?.currentPrincipal, 800)
    }

    func testLedgerModeNonnegativeDebtStillRequiresReview() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack, balance: 0, mode: .ledger)
        XCTAssertThrowsError(try repay(profile, cash, stack))
        XCTAssertTrue(try stack.transactions().isEmpty)
        XCTAssertEqual(profile.currentPrincipal, 1_000)
    }

    func testNormalLedgerTransactionsRemainEditableAndDeletable() throws {
        let stack = try Stack()
        let (_, cash) = try recoveryFixture(stack)
        let ordinary = try LedgerStore.createTransaction(in: stack.context, amount: 10, kind: .expense,
                                                         date: Date(), account: cash)
        try LedgerStore.updateTransaction(ordinary, amount: 20, date: ordinary.date, note: "普通支出",
                                          category: nil, account: cash, reimbursable: false,
                                          isExcluded: false, in: stack.context)
        XCTAssertEqual(ordinary.amount, 20)
        try LedgerStore.delete(ordinary, in: stack.context)
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testRepaymentRejectsBackdatingBeforeEitherAccountAnchor() throws {
        for isPayer in [true, false] {
            let stack = try Stack()
            let (profile, cash, debt) = try repaymentFixture(stack)
            let account = isPayer ? cash : debt
            let anchor = Date(timeIntervalSince1970: 2_000)
            account.openingBalanceEffectiveAt = anchor
            account.openingBalanceQuality = .exact
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.repay(
                profile, amount: 200, fromAccount: cash, book: nil, category: nil,
                date: anchor.addingTimeInterval(-1), in: stack.context
            ))
            XCTAssertTrue(try stack.transactions().isEmpty)
        }
    }

    func testRepaymentUndoRejectsPostRepaymentBalanceCheckpointsOnEitherLeg() throws {
        for isPayer in [true, false] {
            let stack = try Stack()
            let (profile, cash, debt) = try repaymentFixture(stack)
            _ = try repay(profile, cash, stack)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            let account = isPayer ? cash : debt
            let checkpoint = AccountBalanceCheckpointRecord(accountID: account.stableID,
                effectiveAt: event.occurredAt.addingTimeInterval(1), knowledgeCutoff: event.createdAt,
                targetBalance: isPayer ? 1_800 : -800)
            checkpoint.createdAt = event.createdAt.addingTimeInterval(1)
            stack.context.insert(checkpoint)
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context))
            XCTAssertEqual(profile.currentPrincipal, 800)
            XCTAssertEqual(try stack.transactions().count, 1)
        }
    }

    func testRecoveryUndoRejectsLaterBalanceCheckWithoutRemovingArrival() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
        let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
        let checkpoint = AccountBalanceCheckpointRecord(accountID: cash.stableID,
            effectiveAt: event.occurredAt.addingTimeInterval(1), knowledgeCutoff: event.createdAt,
            targetBalance: 2_200)
        checkpoint.createdAt = event.createdAt.addingTimeInterval(1)
        stack.context.insert(checkpoint)
        try stack.context.save()
        XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context))
        XCTAssertEqual(asset.remainingAmount, 800)
        XCTAssertEqual(try stack.transactions().count, 1)
    }

    func testBookDeletePreflightKeepsOrdinaryAndAssetTransactionsAndBook() throws {
        let stack = try Stack()
        let (_, cash) = try recoveryFixture(stack)
        let book = Book(name: "受保护账本")
        stack.context.insert(book)
        let ordinary = try LedgerStore.createTransaction(in: stack.context, amount: 10, kind: .expense,
            date: Date().addingTimeInterval(100), account: cash, book: book)
        let associated = try LedgerStore.createTransaction(in: stack.context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: book)
        stack.context.insert(AssetTransactionLink(assetID: UUID(), transactionID: associated.stableID))
        try stack.context.save()
        XCTAssertThrowsError(try BookStore.deleteWithTransactions(book, in: stack.context))
        XCTAssertEqual(Set(try stack.transactions().map(\.stableID)), Set([ordinary.stableID, associated.stableID]))
        let reload = ModelContext(stack.container)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<Book>()), 1)
        XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 2)
    }

    func testRepaymentInterestCannotBeOffsetButOrdinaryLinkedPurchaseCan() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 100)
        _ = try repay(profile, cash, stack, amount: 150)
        let interest = try XCTUnwrap(stack.transactions().first { $0.eventType == .interest })
        XCTAssertThrowsError(try LedgerStore.createOffset(for: interest, amount: 20, note: "利息退款",
            eventType: .refund, settlementAccount: cash, in: stack.context))
        let purchase = try LedgerStore.createTransaction(in: stack.context, amount: 100, kind: .expense,
            date: Date(), account: cash)
        stack.context.insert(AssetTransactionLink(assetID: UUID(), transactionID: purchase.stableID))
        try stack.context.save()
        let refund = try LedgerStore.createOffset(for: purchase, amount: 20, note: "正常退款",
            eventType: .refund, settlementAccount: cash, in: stack.context)
        XCTAssertEqual(refund.amount, -20)
        XCTAssertEqual(profile.currentPrincipal, 0)
    }

    func testDeletionPreflightAlsoChecksProtectedRefundChildrenOutsideBook() throws {
        let stack = try Stack()
        let (_, cash) = try recoveryFixture(stack)
        let root = try LedgerStore.createTransaction(in: stack.context, amount: 100, kind: .expense,
            date: Date(), account: cash)
        let child = try LedgerStore.createOffset(for: root, amount: 20, note: "退款",
            eventType: .refund, settlementAccount: cash, in: stack.context)
        let asset = PhysicalAsset(name: "已退货物品")
        asset.lifecycle = .returned
        stack.context.insert(asset)
        stack.context.insert(AssetEvent(assetID: asset.stableID, kind: .returned,
            metadataJSON: AssetFinancialCommand.metadata(["refund_transaction_id": child.stableID.uuidString])))
        try stack.context.save()
        XCTAssertThrowsError(try LedgerStore.assertTransactionsCanBeDeleted([root], in: stack.context))
        XCTAssertEqual(try stack.transactions().count, 2)
    }

    func testLedgerSecondRepaymentWithZeroProfileStillUsesActualDebtAndInterest() throws {
        let stack = try Stack()
        let (profile, cash, debt) = try repaymentFixture(stack, balance: -1_000, principal: 100, mode: .ledger)
        _ = try repay(profile, cash, stack, amount: 300)
        XCTAssertEqual(profile.currentPrincipal, 0)
        let second = try repay(profile, cash, stack, amount: 800)
        XCTAssertEqual(second.principal, 700)
        XCTAssertEqual(second.interest, 100)
        XCTAssertEqual(LedgerStore.accountBalance(for: debt, transactions: try stack.transactions()), 0)
        XCTAssertEqual(profile.lifecycle, .paidOff)
    }

    func testLedgerClearsEconomicDebtEvenIfProfilePrincipalIsTooLarge() throws {
        let stack = try Stack()
        let (profile, cash, debt) = try repaymentFixture(stack, balance: -100, principal: 1_000, mode: .ledger)
        _ = try repay(profile, cash, stack, amount: 100)
        XCTAssertEqual(profile.currentPrincipal, 900)
        XCTAssertEqual(LedgerStore.accountBalance(for: debt, transactions: try stack.transactions()), 0)
        XCTAssertEqual(profile.lifecycle, .paidOff)
    }

    func testPausedAndFutureRepaymentsAreRejected() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack)
        profile.lifecycle = .paused
        XCTAssertThrowsError(try repay(profile, cash, stack))
        profile.lifecycle = .active
        XCTAssertThrowsError(try LiabilityStore.repay(profile, amount: 200, fromAccount: cash, book: nil,
            category: nil, date: Date().addingTimeInterval(86_400), in: stack.context))
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testDebtDisplayUsesLedgerBalanceAndDoesNotInventZeroForMissingAccount() throws {
        let stack = try Stack()
        let (profile, cash, debt) = try repaymentFixture(stack, balance: -100, principal: 1_000, mode: .ledger)
        XCTAssertEqual(LiabilitiesView.displayedDebtAmount(for: profile, accounts: [cash, debt],
            transactions: [], checkpoints: []), 100)
        _ = try repay(profile, cash, stack, amount: 100)
        XCTAssertEqual(LiabilitiesView.displayedDebtAmount(for: profile, accounts: [cash, debt],
            transactions: try stack.transactions(), checkpoints: []), 0)
        XCTAssertNil(LiabilitiesView.displayedDebtAmount(for: profile, accounts: [cash],
            transactions: try stack.transactions(), checkpoints: []))
        XCTAssertEqual(profile.currentPrincipal, 900)
    }

    func testLatestRepaymentUsesCommandSequenceWhenAuditTimesAreEqual() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack)
        _ = try repay(profile, cash, stack, amount: 100)
        _ = try repay(profile, cash, stack, amount: 200)
        let events = try stack.context.fetch(FetchDescriptor<AssetEvent>())
        for event in events { event.createdAt = Date(timeIntervalSince1970: 1_000) }
        let latest = try XCTUnwrap(LiabilityStore.latestRepaymentEvent(for: profile, events: events))
        XCTAssertEqual(AssetFinancialCommand.metadata(of: latest)["principal_paid"], "200")
        try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
        XCTAssertEqual(profile.currentPrincipal, 900)
    }

    func testFutureRecoveryIsRejectedWithAndWithoutArrivalAccount() throws {
        for withAccount in [false, true] {
            let stack = try Stack()
            let (asset, cash) = try recoveryFixture(stack)
            XCTAssertThrowsError(try ReceivableStore.recover(asset, amount: 200, in: stack.context,
                account: withAccount ? cash : nil, date: Date().addingTimeInterval(86_400)))
            XCTAssertEqual(asset.remainingAmount, 1_000)
            XCTAssertEqual(asset.lifecycle, .active)
            XCTAssertTrue(try stack.transactions().isEmpty)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 0)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 0)
        }
    }

    func testRecoveryUndoRejectsChangedOriginalAmountEvenWhenRemainingIsUnchanged() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
        asset.originalAmount = 1_200
        try stack.context.save()
        XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context))
        XCTAssertEqual(asset.originalAmount, 1_200)
        XCTAssertEqual(asset.remainingAmount, 800)
        XCTAssertEqual(try stack.transactions().count, 1)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
    }

    func testRecoveryUndoRejectsChangedAfterState() throws {
        for field in ["remaining", "economic_status", "ended_at", "inclusion"] {
            let stack = try Stack()
            let (asset, cash) = try recoveryFixture(stack)
            _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
            switch field {
            case "remaining": asset.remainingAmount = 700
            case "economic_status": asset.economicStatusRaw = "lost"
            case "ended_at": asset.endedAt = Date()
            default: asset.includeInNetWorth = false
            }
            try stack.context.save()
            let remaining = asset.remainingAmount
            XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context), field)
            XCTAssertEqual(asset.remainingAmount, remaining)
            XCTAssertEqual(try stack.transactions().count, 1)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        }
    }

    func testRecoveryUndoRejectsIncompleteOrInconsistentJournal() throws {
        for field in ["original_amount", "remaining_after", "previous_remaining", "previous_lifecycle", "target_account_id"] {
            let stack = try Stack()
            let (asset, cash) = try recoveryFixture(stack)
            _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            var values = AssetFinancialCommand.metadata(of: event)
            values[field] = field == "previous_remaining" ? "950" : nil
            event.metadataJSON = AssetFinancialCommand.metadata(values)
            try stack.context.save()
            XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context), field)
            XCTAssertEqual(asset.remainingAmount, 800)
            XCTAssertEqual(try stack.transactions().count, 1)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        }
    }

    func testRecoveryUndoRejectsMissingArrivalIdentityInsteadOfRestoringOnlyAsset() throws {
        for field in ["transaction", "account", "both"] {
            let stack = try Stack()
            let (asset, cash) = try recoveryFixture(stack)
            let recovery = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
            if field != "account" { recovery.transactionID = nil }
            if field != "transaction" { recovery.targetAccountID = nil }
            try stack.context.save()
            XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context), field)
            XCTAssertEqual(asset.remainingAmount, 800)
            XCTAssertEqual(try stack.transactions().count, 1)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        }
    }

    func testRecoveryUndoRejectsMissingArrivalTransaction() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
        stack.context.delete(try XCTUnwrap(stack.transactions().first))
        try stack.context.save()
        XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context))
        XCTAssertEqual(asset.remainingAmount, 800)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testLegacyRecoveryWithAccountButNoArrivalJournalRequiresReview() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        asset.remainingAmount = 800
        asset.lifecycle = .partiallyRecovered
        stack.context.insert(ReceivableRecovery(receivableID: asset.stableID, amount: 200,
            targetAccountID: cash.stableID))
        try stack.context.save()
        XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context))
        XCTAssertEqual(asset.remainingAmount, 800)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        XCTAssertTrue(try stack.transactions().isEmpty)
    }

    func testRecoveryUndoRejectsMutatedArrivalTransaction() throws {
        for field in ["kind", "date", "settled_at", "excluded", "account", "settlement_account", "to_account", "refund_of"] {
            let stack = try Stack()
            let (asset, cash) = try recoveryFixture(stack)
            _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
            let transaction = try XCTUnwrap(stack.transactions().first)
            switch field {
            case "kind": transaction.kind = .expense
            case "date": transaction.date = transaction.date.addingTimeInterval(60)
            case "settled_at": transaction.settledAt = nil
            case "excluded": transaction.isExcluded = false
            case "account": transaction.account = nil
            case "settlement_account": transaction.settlementAccountID = nil
            case "to_account": transaction.toAccount = cash
            default: transaction.refundOfID = UUID()
            }
            try stack.context.save()
            XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context), field)
            XCTAssertEqual(asset.remainingAmount, 800)
            XCTAssertEqual(try stack.transactions().count, 1)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
        }
    }

    func testRecoveryUndoRejectsRefundChildWithoutDeletingEitherRecord() throws {
        let stack = try Stack()
        let (asset, cash) = try recoveryFixture(stack)
        _ = try ReceivableStore.recover(asset, amount: 200, in: stack.context, account: cash)
        let transaction = try XCTUnwrap(stack.transactions().first)
        let child = MoneyTransaction(amount: -20, kind: .expense, date: transaction.date,
            account: cash, settledAt: transaction.date, settlementAccountID: cash.stableID,
            eventType: .refund, refundOfID: transaction.stableID)
        stack.context.insert(child)
        try stack.context.save()
        XCTAssertThrowsError(try ReceivableStore.undoLatestRecovery(asset, in: stack.context))
        XCTAssertEqual(asset.remainingAmount, 800)
        XCTAssertEqual(try stack.transactions().count, 2)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()), 1)
    }

    func testRepaymentUndoRejectsMutatedPrincipalTransaction() throws {
        for field in ["kind", "date", "settled_at", "excluded", "settlement_account"] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack)
            _ = try repay(profile, cash, stack)
            let transaction = try XCTUnwrap(stack.transactions().first)
            switch field {
            case "kind": transaction.kind = .expense
            case "date": transaction.date = transaction.date.addingTimeInterval(60)
            case "settled_at": transaction.settledAt = nil
            case "excluded": transaction.isExcluded = true
            default: transaction.settlementAccountID = nil
            }
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context), field)
            XCTAssertEqual(profile.currentPrincipal, 800)
            XCTAssertEqual(try stack.transactions().count, 1)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 1)
        }
    }

    func testRepaymentUndoRejectsMutatedInterestTransaction() throws {
        for field in ["kind", "date", "settled_at", "excluded", "settlement_account", "to_account"] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 100)
            _ = try repay(profile, cash, stack, amount: 150)
            let transaction = try XCTUnwrap(stack.transactions().first { $0.eventType == .interest })
            switch field {
            case "kind": transaction.kind = .income
            case "date": transaction.date = transaction.date.addingTimeInterval(60)
            case "settled_at": transaction.settledAt = nil
            case "excluded": transaction.isExcluded = true
            case "settlement_account": transaction.settlementAccountID = nil
            default: transaction.toAccount = cash
            }
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context), field)
            XCTAssertEqual(profile.currentPrincipal, 0)
            XCTAssertEqual(profile.lifecycle, .paidOff)
            XCTAssertEqual(try stack.transactions().count, 2)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 1)
        }
    }

    func testRepaymentUndoRejectsRefundChildrenOnPrincipalOrInterest() throws {
        for isInterest in [false, true] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 100)
            _ = try repay(profile, cash, stack, amount: 150)
            let transaction = try XCTUnwrap(stack.transactions().first {
                $0.eventType == (isInterest ? .interest : .transfer)
            })
            stack.context.insert(MoneyTransaction(amount: -20, kind: .expense, date: transaction.date,
                account: cash, settledAt: transaction.date, settlementAccountID: cash.stableID,
                eventType: .refund, refundOfID: transaction.stableID))
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context))
            XCTAssertEqual(profile.currentPrincipal, 0)
            XCTAssertEqual(try stack.transactions().count, 3)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 1)
        }
    }

    func testNonzeroInterestRequiresValidIdentityAndExistingTransaction() throws {
        for corruption in ["missing_id", "empty_id", "invalid_id", "missing_transaction"] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 100)
            _ = try repay(profile, cash, stack, amount: 150)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            var values = AssetFinancialCommand.metadata(of: event)
            if corruption == "missing_transaction" {
                stack.context.delete(try XCTUnwrap(stack.transactions().first { $0.eventType == .interest }))
            } else {
                values["interest_transaction_id"] = corruption == "missing_id" ? nil
                    : (corruption == "empty_id" ? "" : "not-a-uuid")
                event.metadataJSON = AssetFinancialCommand.metadata(values)
            }
            try stack.context.save()
            let count = try stack.transactions().count
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context), corruption)
            XCTAssertEqual(profile.currentPrincipal, 0)
            XCTAssertEqual(try stack.transactions().count, count)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 1)
        }
    }

    func testZeroInterestCannotCarryAnUnexpectedInterestIdentity() throws {
        let stack = try Stack()
        let (profile, cash, _) = try repaymentFixture(stack)
        _ = try repay(profile, cash, stack)
        let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
        var values = AssetFinancialCommand.metadata(of: event)
        values["interest_transaction_id"] = UUID().uuidString
        event.metadataJSON = AssetFinancialCommand.metadata(values)
        try stack.context.save()
        XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context))
        XCTAssertEqual(profile.currentPrincipal, 800)
        XCTAssertEqual(try stack.transactions().count, 1)
    }

    func testRepaymentUndoRejectsChangedAccountCurrency() throws {
        for isPayer in [false, true] {
            let stack = try Stack()
            let (profile, cash, debt) = try repaymentFixture(stack)
            _ = try repay(profile, cash, stack)
            (isPayer ? cash : debt).currencyCode = "USD"
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context))
            XCTAssertEqual(profile.currentPrincipal, 800)
            XCTAssertEqual(try stack.transactions().count, 1)
        }
    }

    func testActualDebtClearanceRetainsExistingLiabilityKindLifecycleScope() throws {
        for kind in LiabilityKind.allCases {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack, balance: -100, principal: 1_000, mode: .ledger)
            profile.kind = kind
            _ = try repay(profile, cash, stack, amount: 100)
            XCTAssertEqual(profile.currentPrincipal, 900)
            XCTAssertEqual(profile.lifecycle, kind == .personalBorrow ? .paidOff : .active)
            try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
            XCTAssertEqual(profile.currentPrincipal, 1_000)
            XCTAssertEqual(profile.lifecycle, .active)
            XCTAssertTrue(try stack.transactions().isEmpty)
        }
    }

    func testRepaymentUndoRejectsInconsistentBeforeAfterJournal() throws {
        for field in ["principal_before", "principal_paid", "lifecycle_before"] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(stack)
            _ = try repay(profile, cash, stack)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            var values = AssetFinancialCommand.metadata(of: event)
            switch field {
            case "principal_before": values[field] = "1200"
            case "principal_paid": values[field] = "200.001"
            default: values[field] = LiabilityLifecycle.archived.rawValue
            }
            event.metadataJSON = AssetFinancialCommand.metadata(values)
            try stack.context.save()
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context), field)
            XCTAssertEqual(profile.currentPrincipal, 800)
            XCTAssertEqual(profile.lifecycle, .active)
            XCTAssertEqual(try stack.transactions().count, 1)
        }
    }

    func testRepaymentUndoRejectsEditedOriginalPrincipal() throws {
        for original in [Decimal(900), Decimal(1_200)] {
            let stack = try Stack()
            let (profile, cash, debt) = try repaymentFixture(stack)
            _ = try repay(profile, cash, stack)
            try updateOriginalPrincipal(profile, to: original, account: debt, in: stack)
            XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context)) { error in
                guard case .repaymentChanged? = error as? LiabilityStore.Error else {
                    XCTFail("Expected repaymentChanged, got \(error)")
                    return
                }
            }
            let reload = ModelContext(stack.container)
            let saved = try XCTUnwrap(reload.fetch(FetchDescriptor<LiabilityProfile>()).first)
            XCTAssertEqual(saved.originalPrincipal, original)
            XCTAssertEqual(saved.currentPrincipal, 800)
            XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
            XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), 1)
        }
    }

    func testRepaymentUndoPreservesUneditedOriginalPrincipalInBothBalanceModes() throws {
        for mode in [LiabilityBalanceMode.legacyHybrid, .ledger] {
            let stack = try Stack()
            let (profile, cash, _) = try repaymentFixture(
                stack, balance: mode == .ledger ? -100 : -1_000, principal: 1_000, mode: mode
            )
            _ = try repay(profile, cash, stack)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            XCTAssertEqual(AssetFinancialCommand.metadata(of: event)["original_principal"], "1000")
            try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
            let reload = ModelContext(stack.container)
            let saved = try XCTUnwrap(reload.fetch(FetchDescriptor<LiabilityProfile>()).first)
            XCTAssertEqual(saved.originalPrincipal, 1_000)
            XCTAssertEqual(saved.currentPrincipal, 1_000)
            XCTAssertEqual(saved.lifecycle, .active)
            XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
        }
    }

    func testLegacyRepaymentJournalCannotRestorePrincipalAboveEditedOriginal() throws {
        for original in [Decimal(900), Decimal(1_000), Decimal(1_200)] {
            let stack = try Stack()
            let (profile, cash, debt) = try repaymentFixture(stack)
            _ = try repay(profile, cash, stack)
            let event = try XCTUnwrap(stack.context.fetch(FetchDescriptor<AssetEvent>()).first)
            var values = AssetFinancialCommand.metadata(of: event)
            values.removeValue(forKey: "original_principal")
            event.metadataJSON = AssetFinancialCommand.metadata(values)
            try updateOriginalPrincipal(profile, to: original, account: debt, in: stack)
            if original < 1_000 {
                XCTAssertThrowsError(try LiabilityStore.undoLatestRepayment(profile, in: stack.context)) { error in
                    guard case .repaymentChanged? = error as? LiabilityStore.Error else {
                        XCTFail("Expected repaymentChanged, got \(error)")
                        return
                    }
                }
            } else {
                try LiabilityStore.undoLatestRepayment(profile, in: stack.context)
            }
            let reload = ModelContext(stack.container)
            let saved = try XCTUnwrap(reload.fetch(FetchDescriptor<LiabilityProfile>()).first)
            XCTAssertEqual(saved.originalPrincipal, original)
            XCTAssertEqual(saved.currentPrincipal, original < 1_000 ? 800 : 1_000)
            XCTAssertEqual(try reload.fetchCount(FetchDescriptor<MoneyTransaction>()), original < 1_000 ? 1 : 0)
            XCTAssertEqual(try reload.fetchCount(FetchDescriptor<AssetEvent>()), original < 1_000 ? 1 : 2)
        }
    }
}
