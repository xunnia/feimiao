import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 资产中心的总览、资金和物品使用同一份账本数据。
struct AssetsView: View {
    private enum AddAction: String {
        case account
        case receivable
        case newPurchase
        case fromTransaction
        case manualAsset
    }

    private enum AssetTab: String, CaseIterable, Hashable, Identifiable {
        case overview
        case funds
        case items

        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "总览"
            case .funds: return "资金"
            case .items: return "物品"
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

    @State private var selectedTab: AssetTab = .overview
    @State private var showAddEntry = false
    @State private var pendingAddAction: AddAction?
    @State private var showNewAccount = false
    @State private var showNewAsset = false
    @State private var newAssetSource: PhysicalAssetSourceType = .historicalExisting
    @State private var showNewReceivable = false
    @State private var detailAsset: PhysicalAsset?
    @State private var editingReceivable: ReceivableAsset?
    @State private var recoveryAsset: ReceivableAsset?
    @State private var terminalAsset: PhysicalAsset?
    @State private var errorMessage: String?
    @State private var showArchivedFunds = false
    @State private var zeroAccountsExpanded = false
    @State private var editingAccount: Account?
    let opensFirstDetail: Bool
    let startsOnAdd: Bool
    let startsOnPurchase: Bool
    let preselectFirstPurchase: Bool
    @State private var didOpenLaunchDetail = false
    @State private var didOpenLaunchAdd = false
    @State private var didOpenLaunchPurchase = false

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

    private var archivedReceivables: [ReceivableAsset] {
        receivables.filter { !$0.isDeleted && $0.lifecycle == .archived }
    }

    init(
        opensFirstDetail: Bool = false,
        startsOnPhysical: Bool = false,
        startsOnFunds: Bool = false,
        startsOnAdd: Bool = false,
        startsOnPurchase: Bool = false,
        preselectFirstPurchase: Bool = false
    ) {
        self.opensFirstDetail = opensFirstDetail
        self.startsOnAdd = startsOnAdd
        self.startsOnPurchase = startsOnPurchase
        self.preselectFirstPurchase = preselectFirstPurchase
        _selectedTab = State(
            initialValue: startsOnPhysical || opensFirstDetail || startsOnPurchase
                ? .items : (startsOnFunds ? .funds : .overview)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("资产类型", selection: $selectedTab) {
                    ForEach(AssetTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .overview:
                    netWorthSummary
                case .funds:
                    fundsContent
                case .items:
                    physicalContent
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .liquidGlassCanvas()
        .onAppear {
            if startsOnAdd && !didOpenLaunchAdd {
                didOpenLaunchAdd = true
                showAddEntry = true
            }
            if startsOnPurchase && !didOpenLaunchPurchase {
                didOpenLaunchPurchase = true
                newAssetSource = .fromTransaction
                showNewAsset = true
            }
            guard opensFirstDetail, !didOpenLaunchDetail,
                  let first = visibleAssets.first else { return }
            didOpenLaunchDetail = true
            detailAsset = first
        }
        .navigationTitle("资产管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddEntry = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.primary)
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("新增资产")
            }
        }
        .sheet(isPresented: $showAddEntry, onDismiss: openPendingAddAction) {
            addEntrySheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNewAccount) {
            AccountEditorSheet(
                account: nil,
                nextSortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingAccount) { account in
            AccountEditorSheet(account: account, nextSortOrder: account.sortOrder)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNewAsset) {
            PhysicalAssetEditor(
                asset: nil,
                initialSourceType: newAssetSource,
                preselectFirstPurchase: preselectFirstPurchase
            )
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

    private var addEntrySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addEntryGroup("资金") {
                        addEntryRow("添加账户", subtitle: "现金、银行卡、信用卡、存款、贷款", symbol: "wallet.pass", action: .account)
                        Divider().padding(.leading, 58)
                        addEntryRow("添加权益", subtitle: "押金、借出款、应收款、预付余额", symbol: "arrow.down.left.circle", action: .receivable)
                    }
                    addEntryGroup("物品") {
                        addEntryRow("新购买记账", subtitle: "选择付款账户，同时记录物品和支出", symbol: "bag", action: .newPurchase)
                        Divider().padding(.leading, 58)
                        addEntryRow("从已有账单加入", subtitle: "继承购买日期和账本，不重复记支出", symbol: "receipt", action: .fromTransaction)
                        Divider().padding(.leading, 58)
                        addEntryRow("手工补录物品", subtitle: "旧物、赠品或没有购买账单的物品", symbol: "square.and.pencil", action: .manualAsset)
                    }
                }
                .padding(16)
            }
            .liquidGlassCanvas()
            .navigationTitle("添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAddEntry = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .liquidGlassCircleControl(size: 40)
                    .accessibilityLabel("关闭")
                }
            }
        }
    }

    private func addEntryGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0, content: content)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private func addEntryRow(
        _ title: String,
        subtitle: String,
        symbol: String,
        action: AddAction
    ) -> some View {
        Button {
            pendingAddAction = action
            showAddEntry = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assets-add-\(action.rawValue)")
    }

    private func openPendingAddAction() {
        guard let action = pendingAddAction else { return }
        pendingAddAction = nil
        switch action {
        case .account:
            showNewAccount = true
        case .receivable:
            showNewReceivable = true
        case .newPurchase, .fromTransaction, .manualAsset:
            switch action {
            case .newPurchase: newAssetSource = .newPurchaseWithAccount
            case .fromTransaction: newAssetSource = .fromTransaction
            default: newAssetSource = .historicalExisting
            }
            showNewAsset = true
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
        let visible = accounts.filter { !$0.isDeleted }
        let active = visible.filter { $0.status == .active }
        let archived = visible.filter { $0.status == .archived }
        let selected = showArchivedFunds ? archived : active
        let selectedReceivables = showArchivedFunds ? archivedReceivables : visibleReceivables
        let nonZero = selected.filter { showArchivedFunds || balance(for: $0) != 0 }
        let zero = showArchivedFunds ? [] : active.filter { balance(for: $0) == 0 }

        return VStack(alignment: .leading, spacing: 12) {
            if showArchivedFunds {
                Button {
                    showArchivedFunds = false
                } label: {
                    Label("返回当前项目", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .liquidGlassSurface(cornerRadius: 14)
            }
            if !selectedReceivables.isEmpty {
                receivableContent(selectedReceivables, archived: showArchivedFunds)
            }

            ForEach(AccountKind.allCases, id: \.self) { kind in
                let group = nonZero.filter { $0.kind == kind }
                if !group.isEmpty {
                    fundsGroup(kind: kind, accounts: group, archived: showArchivedFunds)
                }
            }

            if !zero.isEmpty {
                VStack(spacing: 0) {
                    Button {
                        zeroAccountsExpanded.toggle()
                    } label: {
                        HStack {
                            Text("已清零账户 (\(zero.count))")
                            Spacer()
                            Image(systemName: zeroAccountsExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(16)
                    }
                    if zeroAccountsExpanded {
                        ForEach(zero) { account in
                            Divider().padding(.horizontal, 14)
                            fundsRow(account, archived: false)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }

            if !showArchivedFunds && (!archived.isEmpty || !archivedReceivables.isEmpty) {
                Button {
                    showArchivedFunds = true
                } label: {
                    HStack {
                        Text("已归档 \(archived.count + archivedReceivables.count) 项")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }

            if selected.isEmpty && selectedReceivables.isEmpty && zero.isEmpty {
                emptySection(showArchivedFunds ? "没有已归档账户" : "还没有资金账户", systemImage: "wallet.pass")
            }
        }
        .accessibilityIdentifier("assets-funds")
    }

    private func balance(for account: Account) -> Decimal {
        LedgerStore.accountBalance(for: account, transactions: transactions, checkpoints: checkpoints)
    }

    private func fundsGroup(kind: AccountKind, accounts group: [Account], archived: Bool) -> some View {
        let currencies = Set(group.map(\.currencyCode))
        let subtotal = group.reduce(Decimal.zero) { $0 + balance(for: $1) }
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(kind.fundsLabel).font(.subheadline.weight(.semibold))
                Text("\(group.count) 个账户").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if currencies.count == 1, let currency = currencies.first {
                    Text(MoneyFormat.string(subtotal, currencyCode: currency))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(subtotal < 0 ? Color.warning : Color.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            ForEach(group.indices, id: \.self) { index in
                if index > 0 { Divider().padding(.horizontal, 16) }
                fundsRow(group[index], archived: archived)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func fundsRow(_ account: Account, archived: Bool) -> some View {
        let amount = balance(for: account)
        return NavigationLink {
            AccountDetailView(account: account)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: account.kind.symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.1), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name).font(.body)
                    Text(account.institution.isEmpty ? account.kind.fundsLabel
                         : "\(account.kind.fundsLabel) · \(account.institution)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(MoneyFormat.string(amount, currencyCode: account.currencyCode))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(amount < 0 ? Color.warning : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingAccount = account
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                account.status = archived ? .active : .archived
                account.archivedAt = archived ? nil : Date()
                account.updatedAt = Date()
                do { try context.save() }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label(archived ? "恢复" : "归档", systemImage: archived ? "arrow.uturn.backward" : "archivebox")
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

    private func receivableContent(_ assets: [ReceivableAsset], archived: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("权益资产", systemImage: "arrow.down.left.circle")
            ForEach(assets) { asset in
                receivableRow(asset, archived: archived)
            }
        }
    }

    private func receivableRow(_ asset: ReceivableAsset, archived: Bool) -> some View {
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
                if !archived && asset.remainingAmount > 0 {
                    Button("收回") { recoveryAsset = asset }
                        .font(.caption.weight(.semibold))
                        .liquidGlassPrimaryPillControl(horizontalPadding: 10, minHeight: 36)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contextMenu {
            if archived {
                Button {
                    do { try ReceivableStore.restore(asset, in: context) }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
            } else {
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

private extension AccountKind {
    var fundsLabel: String {
        switch self {
        case .cash: return "现金"
        case .bankCard: return "储蓄卡"
        case .creditCard: return "信用卡"
        case .savings: return "存款"
        case .investment: return "投资"
        case .loan: return "贷款"
        case .weChat: return "微信"
        case .alipay: return "支付宝"
        case .other: return "其他"
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
    @Query
    private var purchaseLinks: [AssetTransactionLink]

    let asset: PhysicalAsset?
    let preselectFirstPurchase: Bool
    @State private var didPreselectPurchase = false
    @State private var name: String
    @State private var kind: PhysicalAssetKind
    @State private var sourceType: PhysicalAssetSourceType
    @State private var purchasePriceText: String
    @State private var currentValueText: String
    @State private var purchaseValueEdited = false
    @State private var usageLifecycle: PhysicalAssetLifecycle
    @State private var bookID: UUID?
    @State private var paymentAccountID: UUID?
    @State private var purchaseCategoryKey: String?
    @State private var sourceTransactionID: UUID?
    @State private var purchaseSearch = ""
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

    init(
        asset: PhysicalAsset?,
        initialSourceType: PhysicalAssetSourceType = .historicalExisting,
        preselectFirstPurchase: Bool = false
    ) {
        let resolvedSourceType = asset?.sourceType ?? initialSourceType
        self.asset = asset
        self.preselectFirstPurchase = preselectFirstPurchase
        _name = State(initialValue: asset?.name ?? "")
        _kind = State(initialValue: asset?.kind ?? .other)
        _sourceType = State(initialValue: resolvedSourceType)
        _usageLifecycle = State(initialValue:
            asset?.lifecycle == .idle || asset?.usageStatusRaw == "idle" ? .idle : .owned
        )
        _purchasePriceText = State(initialValue: asset.map { "\($0.purchasePrice)" } ?? "")
        _currentValueText = State(initialValue: asset.map { "\($0.currentValue)" } ?? "")
        _bookID = State(initialValue: asset?.bookID)
        _purchaseDateEnabled = State(
            initialValue: asset?.purchaseDate != nil ||
                (asset == nil && resolvedSourceType == .newPurchaseWithAccount)
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
        _includeInNetWorth = State(initialValue: asset?.includeInNetWorth ?? false)
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

    private var purchaseCandidates: [AssetStore.PurchaseCandidate] {
        AssetStore.purchaseCandidates(transactions: sourceTransactions, links: purchaseLinks)
    }

    private var selectedPurchaseCandidate: AssetStore.PurchaseCandidate? {
        purchaseCandidates.first { $0.transaction.stableID == sourceTransactionID }
    }

    private var sourceTransaction: MoneyTransaction? {
        selectedPurchaseCandidate?.transaction
    }

    private var matchingPurchaseCandidates: [AssetStore.PurchaseCandidate] {
        let query = purchaseSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return purchaseCandidates }
        return purchaseCandidates.filter { candidate in
            let transaction = candidate.transaction
            return transaction.note.lowercased().contains(query) ||
                transaction.merchantName.lowercased().contains(query) ||
                transaction.category?.name.lowercased().contains(query) == true ||
                transaction.amount.description.contains(query)
        }
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
            guard let candidate = selectedPurchaseCandidate,
                  let allocationGross,
                  let allocationRefund,
                  MoneyNormalization.cents(allocationGross) > 0,
                  MoneyNormalization.cents(allocationGross) <= candidate.remainingGrossCents,
                  MoneyNormalization.cents(allocationRefund) >= 0,
                  MoneyNormalization.cents(allocationRefund) <= candidate.remainingRefundCents,
                  allocationRefund <= allocationGross else { return false }
            if warrantyEnabled,
               Calendar.current.startOfDay(for: warrantyUntil) <
                Calendar.current.startOfDay(for: candidate.transaction.date) {
                return false
            }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Group {
                if isTransactionSource && sourceTransactionID == nil {
                    purchaseCandidateList
                } else if isTransactionSource {
                    transactionPurchaseForm
                } else {
                    Form {
                        Section {
                            TextField("物品名称", text: $name)
                            Picker("类型", selection: $kind) {
                                ForEach(PhysicalAssetKind.allCases) { kind in
                                    Text(kind.label).tag(kind)
                                }
                            }
                            usagePicker
                            if asset == nil {
                                if isNewPurchase || isTransactionSource {
                                    LabeledContent("物品来源", value: sourceType.label)
                                } else {
                                    Picker("物品来源", selection: $sourceType) {
                                        ForEach(PhysicalAssetSourceType.allCases) { source in
                                            Text(source.label).tag(source)
                                        }
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
                                    HStack {
                                        Text(sourceTransaction.map { $0.note.isEmpty ? "原购买账单" : $0.note } ?? "原购买账单")
                                        Spacer()
                                        Button("重选") { sourceTransactionID = nil }
                                    }
                                    if let candidate = selectedPurchaseCandidate {
                                        Text("可分配 \(MoneyFormat.string(Decimal(candidate.remainingGrossCents) / 100, currencyCode: "CNY")) · 待分配退款 \(MoneyFormat.string(Decimal(candidate.remainingRefundCents) / 100, currencyCode: "CNY"))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                            TextField("当前估值", text: Binding(
                                get: { currentValueText },
                                set: {
                                    currentValueText = $0
                                    if isTransactionSource { purchaseValueEdited = true }
                                }
                            ))
                                .keyboardType(.decimalPad)
                            if isTransactionSource {
                                LabeledContent("账本", value: sourceTransaction?.book?.name ?? "选择账单后继承")
                            } else {
                                Picker("账本", selection: $bookID) {
                                    Text("总账本").tag(Optional<UUID>.none)
                                    ForEach(books) { book in
                                        Text(book.name).tag(Optional(book.stableID))
                                    }
                                }
                            }
                        }
                        Section("资料") {
                            TextField("品牌（可选）", text: $brand)
                            TextField("型号（可选）", text: $model)
                            TextField("存放位置（可选）", text: $location)
                            if isTransactionSource {
                                LabeledContent(
                                    "购买日期",
                                    value: sourceTransaction?.date.formatted(date: .abbreviated, time: .omitted) ?? "选择账单后继承"
                                )
                            } else {
                                Toggle("记录购买日期", isOn: $purchaseDateEnabled)
                                    .disabled(isNewPurchase)
                            }
                            if purchaseDateEnabled && !isTransactionSource {
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
                }
            }
            .onAppear {
                guard preselectFirstPurchase, isTransactionSource, !didPreselectPurchase else { return }
                didPreselectPurchase = true
                sourceTransactionID = purchaseCandidates.first?.transaction.stableID
            }
            .onChange(of: sourceType) { _, next in
                if next == .newPurchaseWithAccount || next == .fromTransaction {
                    purchaseDateEnabled = true
                }
            }
            .onChange(of: sourceTransactionID) { _, id in
                guard let id,
                      let candidate = purchaseCandidates.first(where: {
                          $0.transaction.stableID == id
                      }) else { return }
                let transaction = candidate.transaction
                let defaultRefund = min(candidate.remainingRefundCents, candidate.remainingGrossCents)
                purchaseDateEnabled = true
                purchaseDate = transaction.date
                bookID = transaction.book?.stableID
                allocationGrossText = (Decimal(candidate.remainingGrossCents) / 100).description
                allocationRefundText = (Decimal(defaultRefund) / 100).description
                currentValueText = (Decimal(candidate.remainingGrossCents - defaultRefund) / 100).description
            }
            .onChange(of: allocationGrossText) { _, _ in
                refreshPurchaseValue()
            }
            .onChange(of: allocationRefundText) { _, _ in
                refreshPurchaseValue()
            }
            .navigationTitle(
                asset == nil
                    ? (isNewPurchase ? "记录新购买" : isTransactionSource
                        ? (sourceTransactionID == nil ? "从账单加入物品" : "填写物品信息")
                        : "新增物品")
                    : "编辑物品"
            )
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    LiquidGlassIconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
                }
                if !isTransactionSource || sourceTransactionID != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(asset == nil && !isTransactionSource ? "创建" : "保存") { save() }
                            .disabled(!canSave)
                            .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                    }
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

    static func suggestedPurchaseValue(grossText: String, refundText: String) -> Decimal {
        func cents(_ text: String) -> Int {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            return MoneyNormalization.cents(Decimal(string: clean) ?? .zero)
        }
        let gross = max(0, cents(grossText))
        let refund = max(0, cents(refundText))
        return Decimal(max(0, gross - refund)) / 100
    }

    private func refreshPurchaseValue() {
        guard isTransactionSource, !purchaseValueEdited else { return }
        currentValueText = Self.suggestedPurchaseValue(
            grossText: allocationGrossText,
            refundText: allocationRefundText
        ).description
    }

    private var purchaseCandidateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("选择原购买账单，不会再记一笔支出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索商户、分类或金额", text: $purchaseSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("assets-purchase-search")
                }
                .padding(12)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 2)
                if matchingPurchaseCandidates.isEmpty {
                    ContentUnavailableView(
                        "没有可分配的支出账单",
                        systemImage: "receipt",
                        description: Text("记一笔支出后，再回来把它加入物品")
                    )
                } else {
                    ForEach(matchingPurchaseCandidates, id: \.transaction.stableID) { candidate in
                        Button {
                            sourceTransactionID = candidate.transaction.stableID
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "receipt")
                                    .frame(width: 38, height: 38)
                                    .background(Color.primary.opacity(0.05), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.transaction.note.isEmpty
                                         ? (candidate.transaction.category?.name ?? "支出账单")
                                         : candidate.transaction.note)
                                        .font(.system(size: 15, weight: .medium))
                                    Text("\(Self.purchaseDateText(candidate.transaction.date)) · \(candidate.transaction.book?.name ?? "总账本")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    Text("可分配 \(MoneyFormat.string(Decimal(candidate.remainingGrossCents) / 100, currencyCode: "CNY"))" +
                                         (candidate.remainingRefundCents > 0
                                            ? " · 待分配退款 \(MoneyFormat.string(Decimal(candidate.remainingRefundCents) / 100, currencyCode: "CNY"))"
                                            : ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(MoneyFormat.string(candidate.transaction.amount, currencyCode: "CNY"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .monospacedDigit()
                                    .fixedSize(horizontal: true, vertical: false)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlassSurface(cornerRadius: 20)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("assets-purchase-\(candidate.transaction.stableID)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.primary)
        .liquidGlassCanvas()
    }

    private var usagePicker: some View {
        Picker("使用状态", selection: $usageLifecycle) {
            Text("在用").tag(PhysicalAssetLifecycle.owned)
            Text("闲置").tag(PhysicalAssetLifecycle.idle)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("assets-purchase-usage-status")
    }

    private func purchaseField(
        _ title: String,
        text: Binding<String>,
        hint: String = "",
        helper: String? = nil,
        isMoney: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            HStack {
                if isMoney { Text("¥").foregroundStyle(.secondary) }
                TextField(title, text: text, prompt: Text(hint))
                    .keyboardType(isMoney ? .decimalPad : .default)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            if let helper {
                Text(helper).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var transactionPurchaseForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("第 2 步 · 分配订单金额并补充资料")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: "receipt")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sourceTransaction.map { $0.note.isEmpty ? "原购买账单" : $0.note } ?? "原购买账单")
                            .font(.system(size: 15, weight: .medium))
                        if let sourceTransaction {
                            Text("\(Self.purchaseDateText(sourceTransaction.date)) · \(MoneyFormat.string(sourceTransaction.amount, currencyCode: "CNY"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    LiquidGlassPillButton("重选") { sourceTransactionID = nil }
                }
                .padding(14)
                .liquidGlassSurface(cornerRadius: 20)
                purchaseField("物品名称", text: $name, hint: "例如 无线耳机")
                VStack(alignment: .leading, spacing: 6) {
                    Text("物品分类").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Picker("物品分类", selection: $kind) {
                        ForEach(PhysicalAssetKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("使用状态").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    usagePicker
                }
                if let candidate = selectedPurchaseCandidate {
                    HStack(alignment: .top, spacing: 10) {
                        purchaseField("分配购买金额", text: $allocationGrossText,
                                      helper: "最多 \(MoneyFormat.string(Decimal(candidate.remainingGrossCents) / 100, currencyCode: "CNY"))", isMoney: true)
                            .frame(maxWidth: .infinity)
                        purchaseField("分配退款金额", text: $allocationRefundText,
                                      helper: "最多 \(MoneyFormat.string(Decimal(candidate.remainingRefundCents) / 100, currencyCode: "CNY"))", isMoney: true)
                            .frame(maxWidth: .infinity)
                    }
                }
                purchaseField("当前估值", text: Binding(
                    get: { currentValueText },
                    set: {
                        currentValueText = $0
                        purchaseValueEdited = true
                    }
                ), helper: "默认等于这件物品的净购置成本", isMoney: true)
                Toggle(isOn: $includeInNetWorth) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("计入净资产")
                        Text("按当前估值进入人民币净资产合计")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                purchaseField("品牌（可选）", text: $brand, hint: "例如 Apple")
                purchaseField("型号（可选）", text: $model, hint: "例如 AirPods Pro")
                purchaseField("存放位置（可选）", text: $location, hint: "例如 客厅")
                Toggle("记录保修到期日", isOn: $warrantyEnabled)
                if warrantyEnabled {
                    DatePicker("保修到期", selection: $warrantyUntil, displayedComponents: .date)
                }
                purchaseField("备注（可选）", text: $note, hint: "购买渠道、配置等")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .tint(.primary)
        .liquidGlassCanvas()
    }

    static func purchaseDateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
                    includeInNetWorth: includeInNetWorth,
                    usageLifecycle: usageLifecycle
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
                    includeInNetWorth: includeInNetWorth,
                    usageLifecycle: usageLifecycle
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
                    includeInNetWorth: includeInNetWorth,
                    usageLifecycle: usageLifecycle
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
                    sourceType: sourceType,
                    usageLifecycle: usageLifecycle
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
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(asset == nil ? "创建" : "保存") { save() }
                        .disabled(amount == nil || amount! <= 0 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { save() }
                        .disabled(amount == nil || amount! <= 0)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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
