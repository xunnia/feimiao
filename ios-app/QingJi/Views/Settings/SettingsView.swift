import SwiftUI
import SwiftData
import QingJiCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = CSVDocument()
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("管理") {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label("账户管理", systemImage: "creditcard")
                    }
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入微信 / 支付宝账单", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        exportDocument = CSVDocument(text: CSVExporter.export(transactions.map(\.record)))
                        showExporter = true
                    } label: {
                        Label("导出全部账目为 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(transactions.isEmpty)
                } header: {
                    Text("数据")
                } footer: {
                    Text("在微信「我-服务-钱包-账单」或支付宝「我的-账单」申请导出 CSV 账单后，从文件 App 导入。数据只保存在你的设备和 iCloud。")
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    Text("本地优先存储，开启 iCloud 后自动多端同步；无广告、无账号。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data]
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "qingji-export"
            ) { _ in }
            .alert("导入结果", isPresented: .constant(importMessage != nil)) {
                Button("好") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = String(localized: "无法读取所选文件")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            guard let text = BillTextDecoder.decode(data) else {
                importMessage = String(localized: "无法识别文件编码")
                return
            }
            let imported = try PaymentBillImporter.importBill(fromCSV: text)
            let count = BillRecordSaver.save(imported, context: context)
            importMessage = String(localized: "成功导入 \(count) 笔，跳过 \(imported.skippedRowCount) 行中性或无效交易。")
        } catch is BillImportError {
            importMessage = String(localized: "无法识别账单格式，请确认是微信或支付宝导出的 CSV 文件。")
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

/// 把导入的账单流水落库：按来源匹配账户、按名称匹配分类，匹配不到用「其他」。
enum BillRecordSaver {
    @discardableResult
    static func save(_ result: ImportedBillResult, context: ModelContext) -> Int {
        let categories = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []

        let account: Account? = {
            switch result.source {
            case .weChat: return accounts.first { $0.kind == .weChat } ?? accounts.first
            case .alipay: return accounts.first { $0.kind == .alipay } ?? accounts.first
            case .unknown: return accounts.first
            }
        }()

        func category(for record: TransactionRecord) -> TxCategory? {
            if !record.categoryName.isEmpty,
               let match = categories.first(where: {
                   $0.kind == record.kind &&
                   (record.categoryName.contains($0.name) || $0.name.contains(record.categoryName))
               }) {
                return match
            }
            let fallbackKey = record.kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
            return categories.first { $0.key == fallbackKey }
        }

        for record in result.records {
            context.insert(MoneyTransaction(
                amount: record.amount,
                kind: record.kind,
                date: record.date,
                note: record.note,
                currencyCode: record.currencyCode,
                category: category(for: record),
                account: account
            ))
        }
        try? context.save()
        return result.records.count
    }
}
