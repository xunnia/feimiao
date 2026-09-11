import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// iOS 原生备份页：完整 ZIP、文件 App 导入/导出和本机最近恢复点。
struct BackupView: View {
    @Environment(\.modelContext) private var context

    @State private var backups: [URL] = []
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var document = BackupDocument()
    @State private var pendingRestore: URL?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    exportArchive()
                } label: {
                    Label("导出完整备份", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("从文件恢复", systemImage: "square.and.arrow.down")
                }
                Button {
                    createLocalBackup()
                } label: {
                    Label("立即创建本机恢复点", systemImage: "internaldrive")
                }
            } header: {
                Text("完整备份")
            } footer: {
                Text("备份包含账本、交易、分类、预算、资产、对话、AI 任务审计、定时报表计划和收据附件；API Key、OAuth refresh token 等凭据永不进入备份。")
            }

            Section {
                if backups.isEmpty {
                    Text("还没有本机恢复点")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.path) { url in
                        Button {
                            pendingRestore = url
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(label(for: url))
                                        .foregroundStyle(.primary)
                                    Text(details(for: url))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("本机恢复点")
            } footer: {
                Text("只保留最近 3 份。恢复前会先创建新的本机恢复点，避免误操作后无法回退。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: document,
            contentType: BackupDocument.archiveContentType,
            defaultFilename: "feimiao-backup"
        ) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: BackupDocument.readableContentTypes
        ) { result in
            importArchive(result)
        }
        .confirmationDialog(
            "恢复这份备份？",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认恢复", role: .destructive) {
                if let pendingRestore { restore(pendingRestore) }
                self.pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("当前全部数据会被备份内容替换，恢复前会自动创建一份新的本机恢复点。")
        }
        .alert("备份与恢复", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .task { reload() }
    }

    private func exportArchive() {
        do {
            document = BackupDocument(data: try BackupStore.exportArchive(context: context))
            showExporter = true
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func createLocalBackup() {
        do {
            _ = try BackupStore.createLocalBackup(context: context)
            reload()
            message = "本机恢复点已创建"
        } catch {
            message = "创建失败：\(error.localizedDescription)"
        }
    }

    private func importArchive(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
            }
            _ = try BackupStore.createLocalBackup(context: context)
            let summary = try BackupStore.importData(try Data(contentsOf: url), into: context)
            refreshDerivedState()
            reload()
            message = "恢复完成：\(summary.transactions) 笔交易、\(summary.books) 个账本、\(summary.accounts) 个账户。"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func restore(_ url: URL) {
        do {
            _ = try BackupStore.createLocalBackup(context: context)
            let summary = try BackupStore.importData(try Data(contentsOf: url), into: context)
            refreshDerivedState()
            reload()
            message = "恢复完成：\(summary.transactions) 笔交易。"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func reload() {
        backups = (try? BackupStore.localBackups()) ?? []
    }

    private func refreshDerivedState() {
        WidgetSnapshotWriter.write(context: context)
        Task { @MainActor in
            await AIReportScheduleScheduler.rescheduleAll(in: context)
            if UserDefaults.standard.object(forKey: "qingji.repaymentReminderEnabled") == nil
                || UserDefaults.standard.bool(forKey: "qingji.repaymentReminderEnabled") {
                await RepaymentReminderScheduler.reschedule(context: context)
            } else {
                await RepaymentReminderScheduler.cancelAll()
            }
        }
    }

    private func label(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.hasPrefix("manual-") ? "手动恢复点" : name
    }

    private func details(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let date = values?.contentModificationDate?.formatted(date: .numeric, time: .shortened) ?? ""
        let bytes = values?.fileSize ?? 0
        let size = String(format: "%.1f MB", Double(bytes) / 1_048_576)
        return "\(date) · \(size)"
    }
}
