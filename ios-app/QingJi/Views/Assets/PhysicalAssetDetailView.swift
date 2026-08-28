import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import QingJiCore

/// 物品详情页。资产列表只负责浏览，所有会改变资产生命周期或成本口径的操作
/// 都从这里进入，和 Android 的物品详情页保持同一条可审计操作链。
struct PhysicalAssetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query
    private var transactions: [MoneyTransaction]
    @Query
    private var links: [AssetTransactionLink]
    @Query
    private var events: [AssetEvent]
    @Query
    private var valuations: [AssetValuation]

    let asset: PhysicalAsset

    @State private var activeSheet: DetailSheet?
    @State private var terminalAction: PhysicalAssetLifecycle?
    @State private var showReturnConfirmation = false
    @State private var errorMessage: String?

    private enum DetailSheet: String, Identifiable {
        case editor
        case value
        case sale
        case cost
        case evidence
        case depreciation

        var id: String { rawValue }
    }

    private var isOwned: Bool {
        asset.lifecycle == .owned || asset.lifecycle == .idle
    }

    private var assetLinks: [AssetTransactionLink] {
        links.filter { $0.assetID == asset.stableID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var assetEvents: [AssetEvent] {
        events.filter { $0.assetID == asset.stableID }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var assetValuations: [AssetValuation] {
        valuations.filter { $0.assetID == asset.stableID }
            .sorted { $0.valuedAt > $1.valuedAt }
    }

    private var metrics: PhysicalAssetMetrics? {
        try? AssetStore.metrics(for: asset, in: context, asOf: AppClock.now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    actionGrid
                    metricsSection
                    assetInfoSection
                    linkedTransactionsSection
                    eventSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(asset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("返回")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        actionMenu
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多资产操作")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editor:
                    PhysicalAssetEditor(asset: asset)
                        .presentationDetents([.large])
                case .value:
                    AssetValueUpdateSheet(asset: asset)
                        .presentationDetents([.medium])
                case .sale:
                    AssetSaleSheet(asset: asset)
                        .presentationDetents([.medium, .large])
                case .cost:
                    AssetCostLinkSheet(asset: asset)
                        .presentationDetents([.medium, .large])
                case .evidence:
                    AssetEvidenceSheet(asset: asset)
                        .presentationDetents([.medium, .large])
                case .depreciation:
                    AssetDepreciationSheet(asset: asset)
                        .presentationDetents([.medium, .large])
                }
            }
            .confirmationDialog(
                "结束持有",
                isPresented: Binding(
                    get: { terminalAction != nil },
                    set: { if !$0 { terminalAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let terminalAction {
                    Button(terminalAction.label, role: .destructive) {
                        finishTerminal(terminalAction)
                    }
                }
                Button("取消", role: .cancel) { terminalAction = nil }
            } message: {
                Text("结束后物品不再计入净资产，但历史事件会保留；之后可以从详情页撤销。")
            }
            .confirmationDialog(
                "确认退货",
                isPresented: $showReturnConfirmation,
                titleVisibility: .visible
            ) {
                Button("确认退货", role: .destructive) {
                    perform {
                        _ = try AssetStore.returnToPurchase(asset, in: context)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会按购置账单剩余金额创建退款，并把这件物品的当前价值归零。")
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
    }

    private var hero: some View {
        HStack(spacing: 14) {
            Image(systemName: asset.kind.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.opacity(0.13), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(MoneyFormat.string(asset.currentValue, currencyCode: asset.currencyCode))
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("当前估值 · \(asset.lifecycle.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let metrics, let days = metrics.heldDays.value {
                    Text("已持有 \(days) 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.name)，\(MoneyFormat.string(asset.currentValue, currencyCode: asset.currencyCode))，\(asset.lifecycle.label)")
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            detailAction("编辑资料", systemImage: "pencil", enabled: isOwned) {
                activeSheet = .editor
            }
            detailAction("更新估值", systemImage: "chart.line.uptrend.xyaxis", enabled: isOwned) {
                activeSheet = .value
            }
            if isOwned {
                detailAction("关联支出", systemImage: "link", enabled: true) {
                    activeSheet = .cost
                }
                if asset.usageTrackingEnabled {
                    detailAction("记录使用", systemImage: "hand.tap", enabled: true) {
                        perform { try AssetStore.addUsage(asset, in: context) }
                    }
                }
                detailAction("出售物品", systemImage: "tag", enabled: true) {
                    activeSheet = .sale
                }
                detailAction("确认退货", systemImage: "arrow.uturn.backward", enabled: true) {
                    showReturnConfirmation = true
                }
            } else if asset.lifecycle == .sold {
                detailAction("撤销出售", systemImage: "arrow.uturn.backward", enabled: true) {
                    perform { try AssetStore.undoSale(asset, in: context) }
                }
            } else if asset.lifecycle == .returned {
                detailAction("撤销退货", systemImage: "arrow.uturn.backward", enabled: true) {
                    perform { try AssetStore.undoReturn(asset, in: context) }
                }
            } else {
                detailAction("撤销结束持有", systemImage: "arrow.uturn.backward", enabled: true) {
                    perform { try AssetStore.undoEnd(asset, in: context) }
                }
            }
        }
    }

    private func detailAction(
        _ title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var metricsSection: some View {
        DetailCard(title: "持有指标", systemImage: "gauge.with.dots.needle.67percent") {
            DetailRow(label: "购置成本", value: MoneyFormat.string(asset.purchasePrice, currencyCode: asset.currencyCode))
            if let daily = metrics?.dailyHoldingCost.value {
                DetailRow(label: "日均持有花费", value: "\(MoneyFormat.string(daily, currencyCode: asset.currencyCode))/天")
            } else {
                DetailRow(label: "日均持有花费", value: metrics?.dailyHoldingCost.reason ?? "待确认")
            }
            if let perUse = metrics?.perUseHoldingCost.value {
                DetailRow(label: "每次使用成本", value: "\(MoneyFormat.string(perUse, currencyCode: asset.currencyCode))/次")
            }
            if let ratio = metrics?.valueRetentionRatio.value {
                DetailRow(label: "保值率", value: retentionText(ratio))
            }
            if asset.usageTrackingEnabled {
                DetailRow(label: "累计使用", value: "\(asset.usageCount) 次")
            }
        }
    }

    private var assetInfoSection: some View {
        DetailCard(title: "资产信息", systemImage: "shippingbox") {
            DetailRow(label: "类型", value: asset.kind.label)
            DetailRow(label: "状态", value: asset.lifecycle.label)
            DetailRow(label: "购买日期", value: dateText(asset.purchaseDate))
            DetailRow(label: "保修到期", value: dateText(asset.warrantyUntil))
            if !asset.brand.isEmpty { DetailRow(label: "品牌", value: asset.brand) }
            if !asset.model.isEmpty { DetailRow(label: "型号", value: asset.model) }
            if !asset.location.isEmpty { DetailRow(label: "位置", value: asset.location) }
            if !asset.note.isEmpty { DetailRow(label: "备注", value: asset.note) }
            DetailRow(label: "净资产", value: asset.includeInNetWorth ? "计入" : "不计入")
            DetailRow(label: "照片", value: asset.photoPath.isEmpty ? "未添加" : "已添加")
            DetailRow(label: "凭证", value: asset.invoicePath.isEmpty ? "未添加" : "已添加")
            DetailRow(
                label: "折旧",
                value: asset.depreciationMethod == "linear"
                    ? "线性折旧 · \(asset.usefulLifeMonths) 个月\(asset.depreciationPaused ? " · 已暂停" : "")"
                    : "未开启"
            )
        }
    }

    @ViewBuilder
    private var linkedTransactionsSection: some View {
        if !assetLinks.isEmpty {
            DetailCard(title: "账单关联", systemImage: "link") {
                ForEach(assetLinks, id: \.stableID) { link in
                    let transaction = transactions.first { $0.stableID == link.transactionID }
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.linkType.label)
                                .font(.subheadline.weight(.medium))
                            Text(transaction?.note.isEmpty == false ? transaction!.note : "交易记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(MoneyFormat.string(link.amount, currencyCode: asset.currencyCode))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        if link.linkType != .sourceTransaction && link.linkType != .purchaseTransaction && link.linkType != .saleAccountMovement {
                            Button {
                                perform { try AssetStore.unlinkCost(link, in: context) }
                            } label: {
                                Image(systemName: "link.badge.minus")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("解除关联")
                        }
                    }
                }
            }
        }
    }

    private var eventSection: some View {
        DetailCard(title: "最近事件", systemImage: "clock.arrow.circlepath") {
            if assetEvents.isEmpty {
                Text("还没有资产事件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assetEvents.prefix(8), id: \.stableID) { event in
                    DetailRow(
                        label: event.kind.label,
                        value: "\(dateText(event.occurredAt))\(event.value.map { " · \(MoneyFormat.string($0, currencyCode: asset.currencyCode))" } ?? "")"
                    )
                }
            }
            if !assetValuations.isEmpty {
                Divider().padding(.vertical, 4)
                Text("最近估值")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(assetValuations.prefix(3), id: \.stableID) { valuation in
                    DetailRow(
                        label: dateText(valuation.valuedAt),
                        value: MoneyFormat.string(valuation.value, currencyCode: asset.currencyCode)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var actionMenu: some View {
        Button("编辑资料") { activeSheet = .editor }
        Button("照片与凭证") { activeSheet = .evidence }
        Button("折旧设置") { activeSheet = .depreciation }
        if isOwned {
            Button(asset.lifecycle == .idle ? "标记为在用" : "标记为闲置") {
                perform {
                    try AssetStore.setLifecycle(
                        asset,
                        lifecycle: asset.lifecycle == .idle ? .owned : .idle,
                        in: context,
                        note: asset.lifecycle == .idle ? "恢复在用" : "标记闲置"
                    )
                }
            }
            Button("报废", role: .destructive) { terminalAction = .disposed }
            Button("标记丢失", role: .destructive) { terminalAction = .lost }
            Button("赠送他人") { terminalAction = .gifted }
            Button("归档") { perform { try AssetStore.archive(asset, in: context) } }
        } else if asset.lifecycle == .sold {
            Button("撤销出售") { perform { try AssetStore.undoSale(asset, in: context) } }
        } else if asset.lifecycle == .returned {
            Button("撤销退货状态") { perform { try AssetStore.undoReturn(asset, in: context) } }
        } else if asset.lifecycle == .disposed || asset.lifecycle == .lost || asset.lifecycle == .gifted {
            Button("撤销结束持有") { perform { try AssetStore.undoEnd(asset, in: context) } }
        }
    }

    private func finishTerminal(_ lifecycle: PhysicalAssetLifecycle) {
        terminalAction = nil
        perform { try AssetStore.end(asset, lifecycle: lifecycle, in: context) }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "未填写" }
        return date.formatted(.dateTime.year().month().day())
    }

    private func retentionText(_ ratio: Decimal) -> String {
        let percentage = NSDecimalNumber(decimal: ratio).doubleValue * 100
        return "\(percentage.formatted(.number.precision(.fractionLength(1)))%)"
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .font(.subheadline)
    }
}

private struct AssetValueUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let asset: PhysicalAsset
    @State private var valueText: String
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    init(asset: PhysicalAsset) {
        self.asset = asset
        _valueText = State(initialValue: asset.currentValue.description)
    }

    private var value: Decimal? {
        Decimal(string: valueText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("当前估值", text: $valueText)
                        .keyboardType(.decimalPad)
                    DatePicker("估值日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note)
                }
            }
            .navigationTitle("更新估值")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(value == nil || value! < 0)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let value, value >= 0 else { return }
        do {
            try AssetStore.updateCurrentValue(
                asset,
                value: value,
                at: date,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "手动更新当前价值" : note,
                in: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssetSaleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    let asset: PhysicalAsset
    @State private var grossText = "0"
    @State private var feeText = "0"
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    private var gross: Decimal? { Decimal(string: grossText.replacingOccurrences(of: ",", with: "")) }
    private var fee: Decimal? { Decimal(string: feeText.replacingOccurrences(of: ",", with: "")) }
    private var selectedAccount: Account? { accounts.first { $0.stableID == accountID } }
    private var valid: Bool {
        guard let gross, let fee else { return false }
        return gross >= 0 && fee >= 0 && fee <= gross
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("成交价", text: $grossText)
                        .keyboardType(.decimalPad)
                    TextField("出售费用", text: $feeText)
                        .keyboardType(.decimalPad)
                    Picker("收款账户", selection: $accountID) {
                        Text("不记入账户").tag(Optional<UUID>.none)
                        ForEach(accounts.filter { !$0.isDeleted && $0.status == .active && $0.currencyCode == asset.currencyCode }) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    DatePicker("出售日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note)
                }
                Section {
                    let net = (gross ?? 0) - (fee ?? 0)
                    Text("净到账：\(MoneyFormat.string(net, currencyCode: asset.currencyCode))")
                        .foregroundStyle(.secondary)
                    Text(selectedAccount == nil ? "不指定账户时只结束物品持有，不生成到账流水。" : "到账流水会标记为资产出售，不计入普通收入统计。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("出售物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认出售") { save() }
                        .disabled(!valid)
                }
            }
            .alert("无法出售", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let gross, let fee, valid else { return }
        do {
            _ = try AssetStore.sell(
                asset,
                grossProceeds: gross,
                fee: fee,
                account: selectedAccount,
                at: date,
                note: note,
                in: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssetCostLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query
    private var transactions: [MoneyTransaction]
    @Query
    private var links: [AssetTransactionLink]

    let asset: PhysicalAsset
    @State private var query = ""
    @State private var type: AssetTransactionLinkType = .maintenance
    @State private var errorMessage: String?

    private var candidates: [MoneyTransaction] {
        let linked = Set(links.map(\.transactionID))
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return transactions
            .filter {
                $0.kind == .expense && $0.amount > 0 && $0.refundOfID == nil &&
                !$0.isExcluded && $0.book?.stableID == asset.bookID &&
                $0.currencyCode == asset.currencyCode && !linked.contains($0.stableID) &&
                (normalized.isEmpty || $0.note.lowercased().contains(normalized) || $0.amount.description.contains(normalized))
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("成本类型", selection: $type) {
                    Text("维修保养").tag(AssetTransactionLinkType.maintenance)
                    Text("配件").tag(AssetTransactionLinkType.accessory)
                    Text("保险").tag(AssetTransactionLinkType.insurance)
                    Text("其他支出").tag(AssetTransactionLinkType.otherCost)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                TextField("搜索支出", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                if candidates.isEmpty {
                    ContentUnavailableView("没有可关联支出", systemImage: "link.badge.plus")
                } else {
                    List(candidates, id: \.stableID) { transaction in
                        Button {
                            link(transaction)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.note.isEmpty ? "未命名支出" : transaction.note)
                                    Text(transaction.date.formatted(.dateTime.year().month().day()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("关联持有成本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("无法关联", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func link(_ transaction: MoneyTransaction) {
        do {
            _ = try AssetStore.linkCost(asset, transaction: transaction, type: type, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssetEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let asset: PhysicalAsset
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPath: String
    @State private var invoicePath: String
    @State private var note = ""
    @State private var importingInvoice = false
    @State private var errorMessage: String?

    init(asset: PhysicalAsset) {
        self.asset = asset
        _photoPath = State(initialValue: asset.photoPath)
        _invoicePath = State(initialValue: asset.invoicePath)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("物品照片") {
                    photoPreview
                        .frame(maxWidth: .infinity)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                    if !photoPath.isEmpty {
                        Button("移除照片", role: .destructive) {
                            photoPath = ""
                        }
                    }
                }
                Section("发票与保修单") {
                    TextField("受管文件路径", text: $invoicePath)
                        .textInputAutocapitalization(.never)
                    Button {
                        importingInvoice = true
                    } label: {
                        Label("选择 PDF 或图片", systemImage: "paperclip")
                    }
                    if !invoicePath.isEmpty {
                        Button("移除凭证", role: .destructive) {
                            invoicePath = ""
                        }
                    }
                }
                Section {
                    TextField("说明（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("照片与凭证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onChange(of: photoItem) { _, item in
                if let item { importPhoto(item) }
            }
            .fileImporter(
                isPresented: $importingInvoice,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                importInvoice(result)
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let url = AttachmentStore.url(for: photoPath),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 170)
                .clipShape(.rect(cornerRadius: 12))
        } else {
            ContentUnavailableView("还没有照片", systemImage: "photo")
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                photoPath = try AttachmentStore.save(data: data, fileExtension: "jpg")
                photoItem = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importInvoice(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let accessing = source.startAccessingSecurityScopedResource()
            defer {
                if accessing { source.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: source)
            let extensionName = source.pathExtension.isEmpty ? "bin" : source.pathExtension
            invoicePath = try AttachmentStore.save(data: data, fileExtension: extensionName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let oldPhotoPath = asset.photoPath
            let oldInvoicePath = asset.invoicePath
            try AssetStore.updateEvidence(
                asset,
                photoPath: photoPath,
                thumbnailPath: photoPath,
                invoicePath: invoicePath,
                note: note,
                in: context
            )
            if !oldPhotoPath.isEmpty && oldPhotoPath != photoPath {
                AttachmentStore.remove(oldPhotoPath)
            }
            if !oldInvoicePath.isEmpty && oldInvoicePath != invoicePath {
                AttachmentStore.remove(oldInvoicePath)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssetDepreciationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let asset: PhysicalAsset
    @State private var enabled: Bool
    @State private var baseText: String
    @State private var salvageText: String
    @State private var monthsText: String
    @State private var startDate: Date
    @State private var note = ""
    @State private var errorMessage: String?

    init(asset: PhysicalAsset) {
        self.asset = asset
        _enabled = State(initialValue: asset.depreciationMethod == "linear")
        let base = asset.depreciationBase > 0 ? asset.depreciationBase : asset.purchasePrice
        _baseText = State(initialValue: base.description)
        _salvageText = State(initialValue: asset.salvageValue.description)
        _monthsText = State(initialValue: asset.usefulLifeMonths > 0 ? String(asset.usefulLifeMonths) : "")
        _startDate = State(initialValue: asset.depreciationStartDate ?? asset.purchaseDate ?? Date())
    }

    private var base: Decimal? {
        Decimal(string: baseText.replacingOccurrences(of: ",", with: ""))
    }

    private var salvage: Decimal? {
        Decimal(string: salvageText.replacingOccurrences(of: ",", with: ""))
    }

    private var months: Int? { Int(monthsText.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var valid: Bool {
        guard enabled else { return true }
        guard let base, let salvage, let months else { return false }
        return base > 0 && salvage >= 0 && salvage <= base && months > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用线性折旧", isOn: $enabled)
                    if enabled {
                        TextField("折旧基准金额", text: $baseText)
                            .keyboardType(.decimalPad)
                        TextField("预计残值", text: $salvageText)
                            .keyboardType(.decimalPad)
                        TextField("使用寿命（月）", text: $monthsText)
                            .keyboardType(.numberPad)
                        DatePicker("折旧开始日期", selection: $startDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("按完整月份把价值降到残值，不生成普通收支；手动更新估值后会暂停自动折旧。")
                }
                Section {
                    TextField("说明（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("折旧设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!valid)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try AssetStore.configureDepreciation(
                asset,
                enabled: enabled,
                base: base ?? .zero,
                salvageValue: salvage ?? .zero,
                usefulLifeMonths: months ?? 0,
                startAt: enabled ? startDate : nil,
                note: note,
                in: context
            )
            _ = try AssetStore.applyDepreciation(asOf: AppClock.now, in: context)
            dismiss()
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
