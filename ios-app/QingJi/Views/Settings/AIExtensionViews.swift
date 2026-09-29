import Foundation
import SwiftData
import SwiftUI
import UIKit

/// 安卓 AI 任务中心的 iOS 原生对应页。
@MainActor
struct AITaskCenterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIRequestRunRecord.updatedAt, order: .reverse)
    private var runs: [AIRequestRunRecord]

    var body: some View {
        List {
            if runs.isEmpty {
                ContentUnavailableView(
                    "暂无 AI 任务",
                    systemImage: "checkmark.circle",
                    description: Text("发送消息、AI 记账或生成报告后，任务会显示在这里。")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(runs) { run in
                        NavigationLink {
                            AITaskDetailView(run: run)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: run.mode))
                                    .foregroundStyle(color(for: run.status))
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(run.mode.label)
                                        .font(.body.weight(.medium))
                                    Text(subtitle(for: run))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(run.status.label)
                                    .font(.caption)
                                    .foregroundStyle(color(for: run.status))
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(runs[index])
                        }
                        try? context.save()
                    }
                } header: {
                    Text("最近运行")
                } footer: {
                    Text("任务记录只保存阶段、配置和计数，不保存完整提示词、密钥或原始思考内容。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
    }

    private func subtitle(for run: AIRequestRunRecord) -> String {
        let provider = run.providerLabel.isEmpty ? "未指定服务商" : run.providerLabel
        let model = run.model.isEmpty ? "未指定模型" : run.model
        let time = run.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(provider) · \(model) · \(time)"
    }

    private func icon(for mode: AIRequestMode) -> String {
        switch mode {
        case .record: return "yensign.circle"
        case .chat: return "bubble.left.and.bubble.right"
        case .query: return "magnifyingglass"
        case .report, .scheduledReport: return "doc.text"
        case .importBill: return "arrow.down.doc"
        case .localModel: return "desktopcomputer"
        }
    }

    private func color(for status: AIRequestStatus) -> Color {
        switch status {
        case .failed: return .red
        case .completed, .rolledBack: return .accentColor
        default: return .secondary
        }
    }
}

@MainActor
struct AITaskDetailView: View {
    @Environment(\.modelContext) private var context
    let run: AIRequestRunRecord

    private var events: [AIRequestEventRecord] {
        AIRequestRunStore.events(for: run.stableID, in: context)
    }

    var body: some View {
        List {
            Section("任务") {
                LabeledContent("类型", value: run.mode.label)
                LabeledContent("状态", value: run.status.label)
                if !run.providerLabel.isEmpty {
                    LabeledContent("服务商", value: run.providerLabel)
                }
                if !run.model.isEmpty {
                    LabeledContent("模型", value: run.model)
                }
                LabeledContent("创建时间", value: run.createdAt.formatted(date: .abbreviated, time: .shortened))
                if run.inputCharacters > 0 {
                    LabeledContent("输入字符", value: "\(run.inputCharacters)")
                }
                if run.attachmentCount > 0 {
                    LabeledContent("附件", value: "\(run.attachmentCount)")
                }
                if !run.resultSummary.isEmpty {
                    LabeledContent("结果", value: run.resultSummary)
                }
                if !run.errorMessage.isEmpty {
                    Text(run.errorMessage)
                        .foregroundStyle(.red)
                }
            }
            Section("运行过程") {
                if events.isEmpty {
                    Text("暂无过程记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        HStack(spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.type.label)
                                let details = event.summary.isEmpty
                                    ? (event.count > 0 ? "\(event.count) 项" : "")
                                    : event.summary
                                if !details.isEmpty {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(event.createdAt, format: .dateTime.hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("AI 任务详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// iOS 不能保证后台联网生成 AI 报告，因此保存计划并在到期时提醒用户打开 App。
@MainActor
struct AIReportScheduleView: View {
    @Environment(\.modelContext) private var context
    @Environment(AIProviderStore.self) private var providerStore
    @Query(sort: \AIReportScheduleRecord.updatedAt, order: .reverse)
    private var schedules: [AIReportScheduleRecord]
    @State private var message: String?

    var body: some View {
        List {
            Section {
                if schedules.isEmpty {
                    Text("还没有定时报表")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(schedules) { schedule in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(schedule.title)
                                    .font(.body.weight(.medium))
                                Text("每月 · 下次 \(schedule.nextRunAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { schedule.enabled },
                                set: { value in
                                    do {
                                        try AIReportScheduleStore.setEnabled(
                                            schedule,
                                            enabled: value,
                                            in: context
                                        )
                                        Task { @MainActor in
                                            if value {
                                                if await AIReportScheduleScheduler.requestAuthorization() {
                                                    await AIReportScheduleScheduler.rescheduleAll(in: context)
                                                } else {
                                                    try? AIReportScheduleStore.setEnabled(
                                                        schedule,
                                                        enabled: false,
                                                        in: context
                                                    )
                                                    message = "系统没有允许通知；已关闭这条计划，请到设置中打开通知权限后重试。"
                                                }
                                            } else {
                                                AIReportScheduleScheduler.cancel(schedule)
                                            }
                                        }
                                    } catch {
                                        message = error.localizedDescription
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let schedule = schedules[index]
                            do {
                                AIReportScheduleScheduler.cancel(schedule)
                                try AIReportScheduleStore.delete(schedule, in: context)
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                }
            } footer: {
                Text("计划到期时由 iOS 通知提醒；打开 App 后再使用当前模型生成报告。iOS 不保证像 Android WorkManager 一样在后台固定时刻联网。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("定时报表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    do {
                        _ = try AIReportScheduleStore.createMonthly(
                            in: context,
                            provider: providerStore.selectedAccount
                        )
                        Task { @MainActor in
                            if await AIReportScheduleScheduler.requestAuthorization() {
                                await AIReportScheduleScheduler.rescheduleAll(in: context)
                            } else {
                                message = "系统没有允许通知；计划仍会保存，但到期时不会提醒。"
                            }
                        }
                    } catch {
                        message = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("添加每月报告")
            }
        }
        .alert("定时报表", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

/// 脱敏 AI 诊断：只从本机运行记录汇总健康状态。
@MainActor
struct AIDiagnosticsView: View {
    private struct AccountHealthRow: Identifiable {
        let id: UUID
        let name: String
        let health: AIProviderHealth
    }

    @Environment(AIProviderStore.self) private var providerStore
    @Query(sort: \AIRequestRunRecord.updatedAt, order: .reverse)
    private var runs: [AIRequestRunRecord]

    private var accountHealth: [AccountHealthRow] {
        providerStore.accounts.map { account in
            AccountHealthRow(
                id: account.id,
                name: account.displayName,
                health: providerStore.health(for: account.id)
            )
        }
    }

    private var providers: [(name: String, total: Int, failures: Int, lastError: String)] {
        let grouped = Dictionary(grouping: runs) { $0.providerLabel.isEmpty ? "未指定服务商" : $0.providerLabel }
        return grouped.map { name, items in
            let failures = items.filter { $0.status == .failed }
            return (
                name: name,
                total: items.count,
                failures: failures.count,
                lastError: failures.sorted { $0.updatedAt > $1.updatedAt }.first?.errorMessage ?? ""
            )
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                if accountHealth.isEmpty && providers.isEmpty {
                    Text("还没有 AI 运行记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountHealth, id: \.id) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.name)
                                    .font(.body.weight(.medium))
                                let health = provider.health
                                Text("状态：\(health.statusLabel) · 成功 \(health.successCount) 次 · 失败 \(health.failureCount) 次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if health.averageLatencyMs > 0 {
                                    Text("平均延迟 \(health.averageLatencyMs) ms")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !health.lastError.isEmpty {
                                    Text(health.lastError)
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: healthSymbol(for: provider.health))
                                .foregroundStyle(healthColor(for: provider.health))
                        }
                    }
                }
            } header: {
                Text("账号健康")
            } footer: {
                Text("验证会先读取模型目录，再发送不含账本内容的最小连接请求。")
            }

            Section {
                if providers.isEmpty {
                    Text("还没有 AI 运行记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.name)
                                    .font(.body.weight(.medium))
                                Text("运行 \(provider.total) 次 · 失败 \(provider.failures) 次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !provider.lastError.isEmpty {
                                    Text(provider.lastError)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: provider.failures == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(provider.failures == 0 ? Color.accentColor : .orange)
                        }
                    }
                }
            } header: {
                Text("运行记录")
            } footer: {
                Text("诊断只显示阶段、次数和脱敏错误，不保存或展示 API Key、完整提示词、账本原文或模型思考内容。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
    }

    private func healthSymbol(for health: AIProviderHealth) -> String {
        if health.isCoolingDown { return "exclamationmark.triangle" }
        switch AIProviderVerificationStatus.from(rawValue: health.verificationStatus) {
        case .some(.available): return "checkmark.circle.fill"
        case .some(.needsProxy): return "network"
        case .some(.invalidCredential): return "key.slash"
        case .some(.modelUnavailable): return "cube"
        case .some(.networkError): return "wifi.exclamationmark"
        case .some(.configurationError): return "gearshape.2"
        case .none: return "waveform.path.ecg"
        }
    }

    private func healthColor(for health: AIProviderHealth) -> Color {
        switch AIProviderVerificationStatus.from(rawValue: health.verificationStatus) {
        case .some(.available): return .accentColor
        case .some(.needsProxy), .some(.invalidCredential), .some(.modelUnavailable),
             .some(.networkError), .some(.configurationError):
            return .orange
        case .none: return .secondary
        }
    }
}
