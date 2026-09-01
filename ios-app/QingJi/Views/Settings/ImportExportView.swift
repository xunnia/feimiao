import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QingJiCore

/// 与 Android 抽屉「导入导出」对应。真实文件先进入导入复核页，不能静默入账。
struct ImportExportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = CSVDocument()
    @State private var importMessage: String?
    @State private var pendingImport: ImportedBillResult?
    @State private var showImportReview = false

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("导入微信 / 支付宝账单", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("导入")
            } footer: {
                Text("从文件 App 选择微信或支付宝导出的 CSV / XLSX。所有记录会先进入复核页，确认后才保存。")
            }

            Section {
                Button {
                    let visible = LedgerPolicy.userRecords(from: transactions.map(\.record))
                    exportDocument = CSVDocument(text: CSVExporter.export(visible))
                    showExporter = true
                } label: {
                    Label("导出全部账目为 CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(transactions.isEmpty)
            } header: {
                Text("导出")
            } footer: {
                Text("导出的 CSV 不包含 AI API Key；请把导出文件保存到你信任的位置。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("导入导出")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                .commaSeparatedText,
                .plainText,
                UTType(filenameExtension: "xlsx") ?? .data,
                .data,
            ]
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "qingji-export"
        ) { _ in }
        .sheet(isPresented: $showImportReview) {
            if let pendingImport {
                ImportReviewView(result: pendingImport) { count, skipped in
                    importMessage = "成功导入 \(count) 笔，跳过 \(skipped) 行中性或无效交易。"
                    showImportReview = false
                    self.pendingImport = nil
                }
            }
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "无法读取所选文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let imported: ImportedBillResult
            if url.pathExtension.lowercased() == "xlsx" {
                imported = try XLSXBillImporter.importBill(from: data)
            } else {
                guard let text = BillTextDecoder.decode(data) else {
                    importMessage = "无法识别文件编码"
                    return
                }
                imported = try PaymentBillImporter.importBill(fromCSV: text)
            }
            pendingImport = imported
            showImportReview = true
        } catch is BillImportError {
            importMessage = "无法识别账单格式，请确认是微信或支付宝导出的 CSV 文件。"
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
