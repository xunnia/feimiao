import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 资产中心：资金、物品和权益使用同一张净资产摘要，明细按原生 iOS 交互展开。
struct AssetsView: View {
    private enum AssetTab: String, CaseIterable, Hashable, Identifiable {
        case funds
        case physical
        case receivable

        var id: String { rawValue }
        var label: String {
            switch self {
            case .funds: return "资金"
            case .physical: return "物品"
            case .receivable: return "权益"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query
    private var transactions: [MoneyTransaction]
    @Query(sort: \PhysicalAsset.updatedAt, order: .reverse)
    private var physicalAssets: [PhysicalAsset]
    @Query(sort: \ReceivableAsset.updatedAt, order: .reverse)
    private var receivables: [ReceivableAsset]
    @Query(sort: \LiabilityProfile.updatedAt, order: .reverse)
    private var liabilities: [LiabilityProfile]
    @Query
    private var checkpoints: [AccountBalanceCheckpointRecord]

    @State private var selectedTab: AssetTab = .funds
    @State private var showNewAsset = false
    @State private var showNewReceivable = false
    @State private var detailAsset: PhysicalAsset?
    @State private var editingReceivable: ReceivableAsset?
    @State private var recoveryAsset: ReceivableAsset?
    @State private var terminalAsset: PhysicalAsset?
    @State private var errorMessage: String?
    let opensFirstDetail: Bool
    @State private var didOpenLaunchDetail = false

    private var currentBreakdown: NetWorthStore.Breakdown {
        NetWorthStore.breakdown(
            accounts: accounts,
            transactions: transactions,
            physicalAssets: physicalAssets,
            receivables: receivables,
            liabilities: liabilities,
            checkpoints: checkpoints
        )
    }

    private var visibleAssets: [PhysicalAsset] {
        physicalAssets.filter { !$0.isDeleted && $0.lifecycle != .archived }
    }

    private var visibleReceivables: [ReceivableAsset] {
        receivables.filter { !$0.isDeleted && $0.lifecycle != .archived }
    }

    init(opensFirstDetail: Bool = false, startsOnPhysical: Bool = false) {
        self.opensFirstDetail = opensFirstDetail
        _selectedTab = State(
            initialValue: startsOnPhysical || opensFirstDetail ? .physical : .funds
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                netWorthSummary
                Picker("资产类型", selection: $selectedTab) {
                    ForEach(AssetTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .funds:
                    fundsContent
                case .physical:
                    physicalContent
                case .receivable:
                    receivableContent
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .liquidGlassCanvas()
        .onAppear {
            guard opensFirstDetail, !didOpenLaunchDetail,
                  let first = visibleAssets.first else { return }
            didOpenLaunchDetail = true
            detailAsset = first
        }
        .navigationTitle("资产管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showNewAsset = true
                    } label: {
                        Label("新增物品资产", systemImage: "shippingbox")
                    }
                    Button {
                        showNewReceivable = true
                    } label: {
                        Label("新增权益", systemImage: "arrow.down.left.circle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增资产")
            }
        }
        .sheet(isPresented: $showNewAsset) {
            PhysicalAssetEditor(asset: nil)
                .presentationDetents([.large])
        }
        .sheet(item: $detailAsset) { asset in
            PhysicalAssetDetailView(asset: asset)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showNewReceivable) {
            ReceivableEditor(asset: nil)
                .presentationDetents([.large])
        }
        .sheet(item: $editingReceivable) { asset in
            ReceivableEditor(asset: asset)
                .presentationDetents([.large])
        }
        .sheet(item: $recoveryAsset) { asset in
            ReceivableRecoverySheet(asset: asset)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "结束持有",
            isPresented: Binding(
                get: { terminalAsset != nil },
                set: { if !$0 { terminalAsset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("出售") { finishAsset(.sold) }
            Button("退货") { finishAsset(.returned) }
            Button("报废", role: .destructive) { finishAsset(.disposed) }
            Button("丢失", role: .destructive) { finishAsset(.lost) }
            Button("赠送") { finishAsset(.gifted) }
            Button("取消", role: .cancel) { terminalAsset = nil }
        } message: {
            Text("结束后该物品不再计入净资产，但历史事件会保留。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var netWorthSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("当前净资产", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text(MoneyFormat.string(currentBreakdown.netWorth, currencyCode: "CNY"))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(currentBreakdown.netWorth >= 0 ? Color.primary : Color.red)
            }
            HStack(spacing: 0) {
                summaryMetric("资金", currentBreakdown.cashAssets)
                summaryMetric("投资", currentBreakdown.investmentAssets)
                summaryMetric("物品", currentBreakdown.physicalAssets)
                summaryMetric("权益", currentBreakdown.receivableAssets)
            }
            if currentBreakdown.totalLiabilities > 0 {
                Text("负债 \(MoneyFormat.string(currentBreakdown.totalLiabilities, currencyCode: "CNY"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !currentBreakdown.unsupportedCurrencies.isEmpty {
                Label(
                    "外币未换算：\(currentBreakdown.unsupportedCurrencies.sorted().joined(separator: "、"))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func summaryMetric(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: "CNY"))
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fundsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("账户余额", systemImage: "wallet.pass")
            ForEach(accounts.filter { !$0.isDeleted && $0.status == .active }) { account in
                let balance = LedgerStore.accountBalance(
                    for: account,
                    transactions: transactions,
                    checkpoints: checkpoints
                )
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.kind.symbol)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                                .font(.body.weight(.medium))
                            Text("\(account.kind.isLiability ? "负债账户" : "资产账户") · \(account.currencyCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(MoneyFormat.string(balance, currencyCode: account.currencyCode))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(balance < 0 ? Color.warning : Color.primary)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var physicalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("物品资产", systemImage: "shippingbox")
            if visibleAssets.isEmpty {
                emptySection("还没有物品资产", systemImage: "shippingbox")
            } else {
                ForEach(visibleAssets) { asset in
                    physicalRow(asset)
                }
            }
        }
    }

    private func physicalRow(_ asset: PhysicalAsset) -> some View {
        let metrics = try? AssetStore.metrics(for: asset, in: context, asOf: AppClock.now)
        return Button {
            detailAsset = asset
        } label: {
            HStack(spacing: 12) {
                Image(systemName: asset.kind.symbolName)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(asset.kind.label) · \(asset.lifecycle.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let daily = metrics?.dailyHoldingCost.value {
                        Text("日均持有 \(MoneyFormat.string(daily, currencyCode: asset.currencyCode))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(MoneyFormat.string(asset.currentValue, currencyCode: asset.currencyCode))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                do { try AssetStore.archive(asset, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            Button {
                terminalAsset = asset
            } label: {
                Label("结束持有", systemImage: "checkmark.seal")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                do {
                    try AssetStore.setLifecycle(
                        asset,
                        lifecycle: asset.lifecycle == .idle ? .owned : .idle,
                        in: context
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label(asset.lifecycle == .idle ? "在用" : "闲置", systemImage: "arrow.triangle.2.circlepath")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                terminalAsset = asset
            } label: {
                Label("结束", systemImage: "checkmark.seal")
            }
            .tint(.orange)
            Button {
                do { try AssetStore.archive(asset, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }

    private var receivableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("权益资产", systemImage: "arrow.down.left.circle")
            if visibleReceivables.isEmpty {
                emptySection("还没有权益资产", systemImage: "arrow.down.left.circle")
            } else {
                ForEach(visibleReceivables) { asset in
                    receivableRow(asset)
                }
            }
        }
    }

    private func receivableRow(_ asset: ReceivableAsset) -> some View {
        HStack(spacing: 12) {
            Button {
                editingReceivable = asset
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.left.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(asset.kind.label) · \(asset.lifecycle.label)\(asset.counterparty.isEmpty ? "" : " · \(asset.counterparty)")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(MoneyFormat.string(asset.remainingAmount, currencyCode: asset.currencyCode))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if asset.remainingAmount > 0 {
                    Button("收回") { recoveryAsset = asset }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.glassProminent)
                        .controlSize(.mini)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contextMenu {
            Button {
                do { try ReceivableStore.archive(asset, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                do { try ReceivableStore.setLost(asset, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("标记损失", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.top, 4)
    }

    private func emptySection(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    private func finishAsset(_ lifecycle: PhysicalAssetLifecycle) {
        guard let asset = terminalAsset else { return }
        do {
            try AssetStore.setLifecycle(asset, lifecycle: lifecycle, in: context)
            terminalAsset = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension PhysicalAssetKind {
    var symbolName: String {
        switch self {
        case .digital: return "ipad.and.iphone"
        case .appliance: return "washer"
        case .vehicle: return "car.fill"
        case .property: return "house.fill"
        case .valuables: return "diamond.fill"
        case .collectibles: return "square.stack.3d.up.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .other: return "shippingbox.fill"
        }
    }
}

struct PhysicalAssetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var sourceTransactions: [MoneyTransaction]

    let asset: PhysicalAsset?
    @State private var name: String
    @State private var kind: PhysicalAssetKind
    @State private var sourceType: PhysicalAssetSourceType
    @State private var purchasePriceText: String
    @State private var currentValueText: String
    @State private var bookID: UUID?
    @State private var paymentAccountID: UUID?
    @State private var purchaseCategoryKey: String?
    @State private var sourceTransactionID: UUID?
    @State private var allocationGrossText: String
    @State private var allocationRefundText: String
    @State private var purchaseDateEnabled: Bool
    @State private var purchaseDate: Date
    @State private var brand: String
    @State private var model: String
    @State private var location: String
    @State private var warrantyEnabled: Bool
    @State private var warrantyUntil: Date
    @State private var includeInNetWorth: Bool
    @State private var note: String
    @State private var errorMessage: String?

    init(asset: PhysicalAsset?) {
        let initialSourceType = asset?.sourceType ?? .historicalExisting
        self.asset = asset
        _name = State(initialValue: asset?.name ?? "")
        _kind = State(initialValue: asset?.kind ?? .other)
        _sourceType = State(initialValue: initialSourceType)
        _purchasePriceText = State(initialValue: asset.map { "\($0.purchasePrice)" } ?? "")
        _currentValueText = State(initialValue: asset.map { "\($0.currentValue)" } ?? "")
        _bookID = State(initialValue: asset?.bookID)
        _purchaseDateEnabled = State(
            initialValue: asset?.purchaseDate != nil ||
                (asset == nil && initialSourceType == .newPurchaseWithAccount)
        )
        _purchaseDate = State(initialValue: asset?.purchaseDate ?? Date())
        _paymentAccountID = State(initialValue: nil)
        _purchaseCategoryKey = State(initialValue: nil)
        _sourceTransactionID = State(initialValue: nil)
        _allocationGrossText = State(initialValue: "")
        _allocationRefundText = State(initialValue: "0")
        _brand = State(initialValue: asset?.brand ?? "")
        _model = State(initialValue: asset?.model ?? "")
        _location = State(initialValue: asset?.location ?? "")
        _warrantyEnabled = State(initialValue: asset?.warrantyUntil != nil)
        _warrantyUntil = State(initialValue: asset?.warrantyUntil ?? Date())
        _includeInNetWorth = State(initialValue: asset?.includeInNetWorth ?? true)
        _note = State(initialValue: asset?.note ?? "")
    }

    private var purchasePrice: Decimal? {
        Decimal(string: purchasePriceText.replacingOccurrences(of: ",", with: ""))
    }

    private var currentValue: Decimal? {
        Decimal(string: currentValueText.replacingOccurrences(of: ",", with: ""))
    }

    private var isNewPurchase: Bool {
        asset == nil && sourceType == .newPurchaseWithAccount
    }

    private var isTransactionSource: Bool {
        asset == nil && sourceType == .fromTransaction
    }

    private var eligibleSourceTransactions: [MoneyTransaction] {
        sourceTransactions.filter {
            $0.kind == .expense &&
            $0.amount > 0 &&
            $0.refundOfID == nil &&
            !$0.isExcluded &&
            $0.currencyCode == "CNY"
        }
    }

    private var sourceTransaction: MoneyTransaction? {
        eligibleSourceTransactions.first { $0.stableID == sourceTransactionID }
    }

    private var allocationGross: Decimal? {
        Decimal(string: allocationGrossText.replacingOccurrences(of: ",", with: ""))
    }

    private var allocationRefund: Decimal? {
        Decimal(string: allocationRefundText.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let currentValue,
              currentValue >= 0 else { return false }
        if !purchasePriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let purchasePrice, purchasePrice >= 0 else { return false }
        }
        if isNewPurchase {
            guard let purchasePrice, purchasePrice > 0,
                  paymentAccountID != nil,
                  purchaseDateEnabled else { return false }
        }
        if isTransactionSource {
            guard let sourceTransaction,
                  let allocationGross,
                  let allocationRefund,
                  allocationGross > 0,
                  allocationRefund >= 0,
                  allocationRefund <= allocationGross,
                  allocationGross <= sourceTransaction.amount else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("物品名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(PhysicalAssetKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    if asset == nil {
                        Picker("物品来源", selection: $sourceType) {
                            ForEach(PhysicalAssetSourceType.allCases) { source in
                                Text(source.label).tag(source)
                            }
                        }
                        if isNewPurchase {
                            Picker("付款账户", selection: $paymentAccountID) {
                                Text("选择账户").tag(Optional<UUID>.none)
                                ForEach(accounts.filter {
                                    !$0.isDeleted &&
                                    $0.status == .active &&
                                    $0.currencyCode == "CNY"
                                }) { account in
                                    Text(account.name).tag(Optional(account.stableID))
                                }
                            }
                            Picker("支出分类", selection: $purchaseCategoryKey) {
                                Text("不指定").tag(Optional<String>.none)
                                ForEach(categories.filter {
                                    $0.kind == .expense && !$0.isArchived
                                }) { category in
                                    Label {
                                        Text(category.name)
                                    } icon: {
                                        CategoryIcon(
                                            categoryKey: category.key,
                                            emoji: category.emoji,
                                            size: 24
                                        )
                                    }
                                        .tag(Optional(category.key))
                                }
                            }
                        }
                        if isTransactionSource {
                            Picker("购买账单", selection: $sourceTransactionID) {
                                Text("选择账单").tag(Optional<UUID>.none)
                                ForEach(eligibleSourceTransactions) { transaction in
                                    Text("\(transaction.note.isEmpty ? "未命名支出" : transaction.note) · \(MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode))")
                                        .tag(Optional(transaction.stableID))
                                }
                            }
                            TextField("本物品分配毛额", text: $allocationGrossText)
                                .keyboardType(.decimalPad)
                            TextField("其中已退款", text: $allocationRefundText)
                                .keyboardType(.decimalPad)
                            if let allocationGross, let allocationRefund,
                               allocationGross >= allocationRefund {
                                LabeledContent(
                                    "净购置成本",
                                    value: MoneyFormat.string(
                                        allocationGross - allocationRefund,
                                        currencyCode: "CNY"
                                    )
                                )
                            }
                        }
                    }
                    if isTransactionSource {
                        Text("购置成本由原账单分配金额计算，不能单独修改。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("购置成本", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                    }
                    TextField("当前估值", text: $currentValueText)
                        .keyboardType(.decimalPad)
                    Picker("账本", selection: $bookID) {
                        Text("总账本").tag(Optional<UUID>.none)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                }
                Section("资料") {
                    TextField("品牌（可选）", text: $brand)
                    TextField("型号（可选）", text: $model)
                    TextField("存放位置（可选）", text: $location)
                    Toggle("记录购买日期", isOn: $purchaseDateEnabled)
                        .disabled(isNewPurchase)
                    if purchaseDateEnabled {
                        DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                    }
                    Toggle("记录保修到期日", isOn: $warrantyEnabled)
                    if warrantyEnabled {
                        DatePicker("保修到期", selection: $warrantyUntil, displayedComponents: .date)
                    }
                }
                Section {
                    Toggle("计入净资产", isOn: $includeInNetWorth)
                    TextField("备注（可选）", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                }
            }
            .onChange(of: sourceType) { _, next in
                if next == .newPurchaseWithAccount || next == .fromTransaction {
                    purchaseDateEnabled = true
                }
            }
            .onChange(of: sourceTransactionID) { _, id in
                guard let id,
                      let transaction = eligibleSourceTransactions.first(where: {
                          $0.stableID == id
                      }) else { return }
                purchaseDateEnabled = true
                purchaseDate = transaction.date
                if allocationGrossText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    allocationGrossText = transaction.amount.description
                }
            }
            .navigationTitle(
                asset == nil
                    ? (isNewPurchase ? "记录新购买" : "新增物品")
                    : "编辑物品"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(asset == nil ? "创建" : "保存") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let currentValue, canSave else { return }
        let purchasePrice = purchasePrice ?? .zero
        let cleanPurchaseDate = purchaseDateEnabled ? purchaseDate : nil
        let cleanWarranty = warrantyEnabled ? warrantyUntil : nil
        do {
            if let asset {
                try AssetStore.update(
                    asset,
                    in: context,
                    name: name,
                    kind: kind,
                    purchasePrice: purchasePrice,
                    currentValue: currentValue,
                    book: books.first { $0.stableID == bookID },
                    purchaseDate: cleanPurchaseDate,
                    warrantyUntil: cleanWarranty,
                    brand: brand,
                    model: model,
                    location: location,
                    note: note,
                    includeInNetWorth: includeInNetWorth
                )
            } else if isTransactionSource {
                guard let sourceTransaction,
                      let allocationGross,
                      let allocationRefund else { return }
                _ = try AssetStore.createFromTransaction(
                    in: context,
                    transaction: sourceTransaction,
                    name: name,
                    kind: kind,
                    allocatedGrossCents: MoneyNormalization.cents(allocationGross),
                    allocatedRefundCents: MoneyNormalization.cents(allocationRefund),
                    currentValue: currentValue,
                    brand: brand,
                    model: model,
                    location: location,
                    warrantyUntil: cleanWarranty,
                    note: note,
                    includeInNetWorth: includeInNetWorth
                )
            } else if isNewPurchase {
                guard let paymentAccountID,
                      let paymentAccount = accounts.first(where: {
                          $0.stableID == paymentAccountID
                      }),
                      let cleanPurchaseDate else { return }
                let purchaseCategory = categories.first {
                    $0.key == purchaseCategoryKey && $0.kind == .expense
                }
                _ = try AssetStore.createPurchased(
                    in: context,
                    name: name,
                    kind: kind,
                    purchasePrice: purchasePrice,
                    currentValue: currentValue,
                    account: paymentAccount,
                    category: purchaseCategory,
                    book: books.first { $0.stableID == bookID },
                    purchaseDate: cleanPurchaseDate,
                    brand: brand,
                    model: model,
                    location: location,
                    warrantyUntil: cleanWarranty,
                    note: note,
                    includeInNetWorth: includeInNetWorth
                )
            } else {
                _ = try AssetStore.create(
                    in: context,
                    name: name,
                    kind: kind,
                    purchasePrice: purchasePrice,
                    currentValue: currentValue,
                    book: books.first { $0.stableID == bookID },
                    purchaseDate: cleanPurchaseDate,
                    brand: brand,
                    model: model,
                    location: location,
                    warrantyUntil: cleanWarranty,
                    note: note,
                    includeInNetWorth: includeInNetWorth,
                    sourceType: sourceType
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReceivableEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder)
    private var books: [Book]

    let asset: ReceivableAsset?
    @State private var name: String
    @State private var kind: ReceivableKind
    @State private var amountText: String
    @State private var counterparty: String
    @State private var bookID: UUID?
    @State private var dueDateEnabled: Bool
    @State private var dueDate: Date
    @State private var includeInNetWorth: Bool
    @State private var note: String
    @State private var errorMessage: String?

    init(asset: ReceivableAsset?) {
        self.asset = asset
        _name = State(initialValue: asset?.name ?? "")
        _kind = State(initialValue: asset?.kind ?? .other)
        _amountText = State(initialValue: asset.map { "\($0.originalAmount)" } ?? "")
        _counterparty = State(initialValue: asset?.counterparty ?? "")
        _bookID = State(initialValue: asset?.bookID)
        _dueDateEnabled = State(initialValue: asset?.dueDate != nil)
        _dueDate = State(initialValue: asset?.dueDate ?? Date())
        _includeInNetWorth = State(initialValue: asset?.includeInNetWorth ?? true)
        _note = State(initialValue: asset?.note ?? "")
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("权益名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(ReceivableKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("原始金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("对方（可选）", text: $counterparty)
                    Picker("账本", selection: $bookID) {
                        Text("总账本").tag(Optional<UUID>.none)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                }
                Section {
                    Toggle("设置到期日", isOn: $dueDateEnabled)
                    if dueDateEnabled {
                        DatePicker("到期日", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("计入净资产", isOn: $includeInNetWorth)
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(asset == nil ? "新增权益" : "编辑权益")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(asset == nil ? "创建" : "保存") { save() }
                        .disabled(amount == nil || amount! <= 0 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let amount else { return }
        do {
            if let asset {
                try ReceivableStore.update(
                    asset,
                    in: context,
                    name: name,
                    kind: kind,
                    originalAmount: amount,
                    book: books.first { $0.stableID == bookID },
                    counterparty: counterparty,
                    dueDate: dueDateEnabled ? dueDate : nil,
                    note: note,
                    includeInNetWorth: includeInNetWorth
                )
            } else {
                _ = try ReceivableStore.create(
                    in: context,
                    name: name,
                    kind: kind,
                    originalAmount: amount,
                    counterparty: counterparty,
                    dueDate: dueDateEnabled ? dueDate : nil,
                    book: books.first { $0.stableID == bookID },
                    note: note,
                    includeInNetWorth: includeInNetWorth
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReceivableRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    let asset: ReceivableAsset
    @State private var amountText: String
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    init(asset: ReceivableAsset) {
        self.asset = asset
        _amountText = State(initialValue: "\(asset.remainingAmount)")
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("剩余可收回 \(MoneyFormat.string(asset.remainingAmount, currencyCode: asset.currencyCode))")
                        .foregroundStyle(.secondary)
                    TextField("本次收回金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("到账账户（可选）", selection: $accountID) {
                        Text("暂不指定").tag(Optional<UUID>.none)
                        ForEach(accounts.filter { !$0.isDeleted && $0.status == .active }) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    DatePicker("收回日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note)
                }
            }
            .navigationTitle("收回权益")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { save() }
                        .disabled(amount == nil || amount! <= 0)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let amount else { return }
        do {
            _ = try ReceivableStore.recover(
                asset,
                amount: amount,
                in: context,
                account: accounts.first { $0.stableID == accountID },
                date: date,
                note: note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
