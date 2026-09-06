import Foundation
import SwiftUI
import FeiMiaoData
import FeiMiaoDomain

private struct AppBootstrapPayload: @unchecked Sendable {
    let books: [LedgerBook]
    let accounts: [LedgerAccount]
    let categories: [LedgerCategory]
    let tags: [LedgerTag]
    let selectedBookID: Int64?
    let hasAnyTransactions: Bool
    let home: HomeMonthSnapshot
}

private struct LedgerLoadPayload: @unchecked Sendable {
    let transactions: [LedgerTransaction]
    let summary: LedgerSummary
    let netAmounts: [Int64: MoneyAmount]
    let accountBalances: [Int64: MoneyAmount]
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var books: [LedgerBook] = []
    @Published private(set) var accounts: [LedgerAccount] = []
    @Published private(set) var categories: [LedgerCategory] = []
    @Published private(set) var tags: [LedgerTag] = []
    @Published private(set) var transactions: [LedgerTransaction] = []
    @Published private(set) var summary = LedgerSummary()
    @Published private(set) var netAmounts: [Int64: MoneyAmount] = [:]
    @Published private(set) var accountBalances: [Int64: MoneyAmount] = [:]
    @Published private(set) var hasAnyTransactions = false
    @Published private var homeSnapshot: HomeMonthSnapshot?
    @Published private(set) var selectedHomeMonth: Date
    @Published private(set) var isHomeLoading = false
    @Published private(set) var isLedgerLoading = true
    @Published private(set) var isImportingBackup = false
    @Published private(set) var isReady = false
    @Published var selectedBookID: Int64?
    @Published var presentedError: String?

    private(set) var repository: LedgerRepository?
    private(set) var databaseURL: URL?
    private var homeLoadTask: Task<Void, Never>?
    private var homeLoadGeneration: UInt = 0
    private var ledgerLoadTask: Task<Void, Never>?
    private var ledgerLoadGeneration: UInt = 0

    init() {
        selectedHomeMonth = Self.monthStart(containing: .now)
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let url = try AppDatabase.defaultURL()
                let database = try AppDatabase(url: url)
                let repository = LedgerRepository(database: database)
                #if DEBUG && targetEnvironment(simulator)
                try SimulatorDemoSeeder.seedIfNeeded(repository: repository)
                #endif
                let books = try repository.books()
                let accounts = try repository.accounts()
                let categories = try repository.categories(includeHidden: true)
                let tags = try repository.tags()
                let storedBook = try repository.setting(for: "ios_selected_book")
                let selectedBookID: Int64?
                if let storedBook,
                   storedBook != "total",
                   let candidate = Int64(storedBook),
                   books.contains(where: { $0.id == candidate }) {
                    selectedBookID = candidate
                } else {
                    selectedBookID = nil
                }
                let monthStart = Self.monthStart(containing: .now)
                guard let nextMonthStart = Self.calendar.date(
                    byAdding: .month,
                    value: 1,
                    to: monthStart
                ) else {
                    throw LedgerRepositoryError.invalidDateRange
                }
                let payload = AppBootstrapPayload(
                    books: books,
                    accounts: accounts,
                    categories: categories,
                    tags: tags,
                    selectedBookID: selectedBookID,
                    hasAnyTransactions: try repository.hasAnyVisibleTransaction(),
                    home: try repository.homeMonthSnapshot(
                        bookID: selectedBookID,
                        monthStart: monthStart,
                        nextMonthStart: nextMonthStart
                    )
                )
                return (url, repository, payload)
            }.value
            let (url, repository, payload) = result
            databaseURL = url
            self.repository = repository
            books = payload.books
            accounts = payload.accounts
            categories = payload.categories
            tags = payload.tags
            selectedBookID = payload.selectedBookID
            selectedHomeMonth = payload.home.monthStart
            hasAnyTransactions = payload.hasAnyTransactions
            homeSnapshot = payload.home
            homeLoadGeneration &+= 1
            isHomeLoading = false
            summary = payload.home.summary
            netAmounts = payload.home.netAmounts
            isReady = true
            scheduleLedgerReload()
        } catch {
            databaseURL = nil
            repository = nil
            presentedError = "无法打开账本：\(error.localizedDescription)"
            isLedgerLoading = false
            isReady = true
        }
    }

    var defaultBookID: Int64? {
        books.min {
            if $0.sortOrder == $1.sortOrder { return $0.id < $1.id }
            return $0.sortOrder < $1.sortOrder
        }?.id
    }

    var homeTransactions: [LedgerTransaction] {
        currentHomeSnapshot?.transactions ?? []
    }

    var homeSummary: LedgerSummary {
        currentHomeSnapshot?.summary ?? LedgerSummary()
    }

    var homeNetAmounts: [Int64: MoneyAmount] {
        currentHomeSnapshot?.netAmounts ?? [:]
    }

    var canAdvanceHomeMonth: Bool {
        selectedHomeMonth < Self.monthStart(containing: .now)
    }

    func setSelectedHomeMonth(_ date: Date) {
        let currentMonth = Self.monthStart(containing: .now)
        let requestedMonth = Self.monthStart(containing: date)
        let targetMonth = min(requestedMonth, currentMonth)
        guard targetMonth != selectedHomeMonth else {
            if currentHomeSnapshot == nil { reloadHomeMonth() }
            return
        }
        selectedHomeMonth = targetMonth
        reloadHomeMonth()
    }

    func stepHomeMonth(by offset: Int) {
        guard offset != 0,
              let target = Self.calendar.date(
                byAdding: .month,
                value: offset,
                to: selectedHomeMonth
              ) else { return }
        setSelectedHomeMonth(target)
    }

    func resetHomeMonthToCurrent() {
        setSelectedHomeMonth(.now)
    }

    func setSelectedBook(_ id: Int64?) {
        guard selectedBookID != id else { return }
        selectedBookID = id
        transactions = []
        netAmounts = [:]
        summary = LedgerSummary()
        isLedgerLoading = true
        do {
            try repository?.setSetting(id.map { String($0) } ?? "total", for: "ios_selected_book")
        } catch {
            report(error)
        }
        reloadLedger()
    }

    func reloadAll() {
        guard let repository else { return }
        do {
            books = try repository.books()
            accounts = try repository.accounts()
            categories = try repository.categories(includeHidden: true)
            tags = try repository.tags()
            hasAnyTransactions = try repository.hasAnyVisibleTransaction()
            if selectedBookID == nil,
               let stored = try repository.setting(for: "ios_selected_book"),
               stored != "total",
               let storedID = Int64(stored),
               books.contains(where: { $0.id == storedID }) {
                selectedBookID = storedID
            } else if let selectedBookID,
                      !books.contains(where: { $0.id == selectedBookID }) {
                self.selectedBookID = nil
                try repository.setSetting("total", for: "ios_selected_book")
            }
            reloadHomeMonth()
            scheduleLedgerReload()
        } catch {
            report(error)
        }
    }

    func reloadLedger() {
        guard repository != nil else { return }
        reloadHomeMonth()
        scheduleLedgerReload()
    }

    nonisolated private static func loadLedgerPayload(
        repository: LedgerRepository,
        bookID: Int64?
    ) throws -> LedgerLoadPayload {
        let filter = TransactionFilter(bookID: bookID)
        let records = try repository.transactions(filter: filter)
        let calendar = Calendar.current
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        )
        let nextMonth = monthStart.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        let summary = try repository.summary(
            filter: TransactionFilter(
                bookID: bookID,
                startDate: monthStart,
                endDate: nextMonth?.addingTimeInterval(-0.001)
            )
        )
        return LedgerLoadPayload(
            transactions: records,
            summary: summary,
            netAmounts: try repository.netAmounts(for: records),
            accountBalances: try repository.accountBalances()
        )
    }

    func transactions(matching filter: TransactionFilter) -> [LedgerTransaction] {
        guard let repository else { return [] }
        do {
            return try repository.transactions(filter: filter)
        } catch {
            report(error)
            return []
        }
    }

    @discardableResult
    func saveTransaction(_ draft: TransactionDraft) -> LedgerTransaction? {
        guard let repository else { return nil }
        do {
            let record = try repository.saveTransaction(draft)
            reloadAll()
            return record
        } catch {
            report(error)
            return nil
        }
    }

    func deleteTransaction(_ id: Int64) {
        perform {
            try repository?.deleteTransaction(id: id)
        }
    }

    func createBook(name: String, icon: String, cover: String, remark: String, includeInTotal: Bool) {
        perform {
            try repository?.createBook(
                name: name,
                icon: icon,
                cover: cover,
                remark: remark,
                includeInTotal: includeInTotal
            )
        }
    }

    func updateBook(_ book: LedgerBook) {
        perform { try repository?.updateBook(book) }
    }

    func deleteBook(_ id: Int64) {
        perform { try repository?.deleteBook(id: id) }
    }

    func createAccount(
        name: String,
        type: String,
        openingBalance: MoneyAmount,
        includeInNetWorth: Bool,
        institution: String
    ) {
        perform {
            try repository?.createAccount(
                name: name,
                type: type,
                openingBalance: openingBalance,
                includeInNetWorth: includeInNetWorth,
                institution: institution
            )
        }
    }

    func updateAccount(_ account: LedgerAccount) {
        perform { try repository?.updateAccount(account) }
    }

    func deleteAccount(_ id: Int64) {
        perform { try repository?.deleteAccount(id: id) }
    }

    func accountIsInUse(_ id: Int64) -> Bool? {
        guard let repository else { return nil }
        do {
            return try repository.accountIsInUse(id: id)
        } catch {
            report(error)
            return nil
        }
    }

    func createCategory(name: String, emoji: String, kind: TransactionKind, parentID: Int64?) {
        perform {
            try repository?.createCategory(name: name, emoji: emoji, kind: kind, parentID: parentID)
        }
    }

    func updateCategory(_ category: LedgerCategory) {
        perform { try repository?.updateCategory(category) }
    }

    func deleteCategory(_ id: Int64) {
        perform { try repository?.deleteCategory(id: id) }
    }

    func createTag(name: String, colorARGB: Int64) {
        perform { try repository?.createTag(name: name, colorARGB: colorARGB) }
    }

    func updateTag(_ tag: LedgerTag) {
        perform { try repository?.updateTag(tag) }
    }

    func deleteTag(_ id: Int64) {
        perform { try repository?.deleteTag(id: id) }
    }

    func saveReceipt(_ data: Data) throws -> String {
        guard let databaseURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }

    /// Removes only files managed by this app's receipts directory. Imported
    /// legacy paths outside the sandbox are never touched.
    func discardManagedReceipt(at path: String) {
        guard let databaseURL, !path.isEmpty else { return }
        do {
            if try repository?.receiptIsReferenced(path) == true { return }
        } catch {
            report(error)
            return
        }
        let root = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("receipts", isDirectory: true)
            .standardizedFileURL
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return }
        do {
            if FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.removeItem(at: candidate)
            }
        } catch {
            report(error)
        }
    }

    func importAndroidBackup(from url: URL) async -> AndroidBackupImportResult? {
        guard let repository, !isImportingBackup else { return nil }
        isImportingBackup = true
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope { url.stopAccessingSecurityScopedResource() }
            isImportingBackup = false
        }
        do {
            let database = repository.database
            let result = try await Task.detached(priority: .userInitiated) {
                try AndroidBackupImporter(database: database).importBackup(from: url)
            }.value
            selectedBookID = nil
            reloadAll()
            return result
        } catch {
            report(error)
            return nil
        }
    }

    func category(for id: Int64?) -> LedgerCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func account(for id: Int64?) -> LedgerAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func book(for id: Int64?) -> LedgerBook? {
        guard let id else { return nil }
        return books.first { $0.id == id }
    }

    func netAmount(for transaction: LedgerTransaction) -> MoneyAmount {
        netAmounts[transaction.id] ?? transaction.amount
    }

    func netAmount(forHomeTransaction transaction: LedgerTransaction) -> MoneyAmount {
        homeNetAmounts[transaction.id] ?? transaction.amount
    }

    private var currentHomeSnapshot: HomeMonthSnapshot? {
        guard let homeSnapshot,
              homeSnapshot.bookID == selectedBookID,
              homeSnapshot.monthStart == selectedHomeMonth else { return nil }
        return homeSnapshot
    }

    private func scheduleLedgerReload() {
        guard let repository else {
            ledgerLoadTask?.cancel()
            ledgerLoadTask = nil
            ledgerLoadGeneration &+= 1
            isLedgerLoading = false
            return
        }
        ledgerLoadTask?.cancel()
        ledgerLoadTask = nil
        ledgerLoadGeneration &+= 1
        let generation = ledgerLoadGeneration
        let bookID = selectedBookID
        isLedgerLoading = true

        ledgerLoadTask = Task { [weak self, repository] in
            do {
                let payload = try await Task.detached(priority: .utility) {
                    try Self.loadLedgerPayload(
                        repository: repository,
                        bookID: bookID
                    )
                }.value
                try Task.checkCancellation()
                guard let self,
                      self.ledgerLoadGeneration == generation,
                      self.selectedBookID == bookID else { return }
                self.transactions = payload.transactions
                self.summary = payload.summary
                self.netAmounts = payload.netAmounts
                self.accountBalances = payload.accountBalances
                self.isLedgerLoading = false
                self.ledgerLoadTask = nil
            } catch is CancellationError {
                guard let self,
                      self.ledgerLoadGeneration == generation else { return }
                self.isLedgerLoading = false
                self.ledgerLoadTask = nil
            } catch {
                guard let self,
                      self.ledgerLoadGeneration == generation else { return }
                self.isLedgerLoading = false
                self.ledgerLoadTask = nil
                self.report(error)
            }
        }
    }

    private func reloadHomeMonth() {
        guard let repository else {
            homeLoadTask?.cancel()
            homeLoadTask = nil
            homeLoadGeneration &+= 1
            homeSnapshot = nil
            isHomeLoading = false
            return
        }
        // SQLite reads finish synchronously once started, so the generation also
        // prevents a cancelled request from publishing after a faster new one.
        homeLoadTask?.cancel()
        homeLoadTask = nil
        homeLoadGeneration &+= 1
        let generation = homeLoadGeneration

        let monthStart = selectedHomeMonth
        guard let nextMonthStart = Self.calendar.date(
            byAdding: .month,
            value: 1,
            to: monthStart
        ) else {
            homeSnapshot = nil
            isHomeLoading = false
            return
        }
        let bookID = selectedBookID

        isHomeLoading = true

        homeLoadTask = Task { [weak self, repository] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try repository.homeMonthSnapshot(
                        bookID: bookID,
                        monthStart: monthStart,
                        nextMonthStart: nextMonthStart
                    )
                }.value
                try Task.checkCancellation()
                guard let self,
                      self.homeLoadGeneration == generation,
                      self.selectedBookID == bookID,
                      self.selectedHomeMonth == monthStart else { return }
                self.homeSnapshot = snapshot
                self.isHomeLoading = false
                self.homeLoadTask = nil
            } catch is CancellationError {
                guard let self, self.homeLoadGeneration == generation else { return }
                self.isHomeLoading = false
                self.homeLoadTask = nil
            } catch {
                guard let self, self.homeLoadGeneration == generation else { return }
                self.isHomeLoading = false
                self.homeLoadTask = nil
                self.report(error)
            }
        }
    }

    nonisolated private static var calendar: Calendar {
        Calendar.autoupdatingCurrent
    }

    nonisolated private static func monthStart(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            reloadAll()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        presentedError = error.localizedDescription
    }
}
