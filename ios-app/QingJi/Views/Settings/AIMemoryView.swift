import SwiftData
import SwiftUI

/// 安卓“可控记忆”的 iOS 原生页面；删除记忆不会修改历史账单或对话。
struct AIMemoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIMemoryRecord.updatedAt, order: .reverse)
    private var memories: [AIMemoryRecord]
    @State private var showEditor = false
    @State private var errorMessage: String?

    private var activeMemories: [AIMemoryRecord] {
        memories.filter(\.isActive)
    }

    var body: some View {
        List {
            Section {
                Text("只有你明确保存并授权的内容才会用于后续 AI 请求；删除后只影响以后，不会改历史账单。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("已授权记忆") {
                if activeMemories.isEmpty {
                    Text("还没有已授权记忆")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMemories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.phrase)
                                .font(.body.weight(.medium))
                            Text(memory.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                do { try AIMemoryStore.delete(memory, in: context) }
                                catch { errorMessage = error.localizedDescription }
                            } label: {
                                Label("忘掉", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            Section {
                Button("忘记全部记忆", role: .destructive) {
                    do { try AIMemoryStore.forgetAll(in: context) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("可控记忆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加记忆")
            }
        }
        .sheet(isPresented: $showEditor) {
            AIMemoryEditor()
        }
        .alert("记忆", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct AIMemoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var phrase = ""
    @State private var content = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("记忆内容") {
                    TextField("触发短语，例如：我不吃辣", text: $phrase)
                    TextField("喵要记住什么", text: $content, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Text("保存后，这条记忆会在匹配到触发短语时作为上下文发送给当前服务商。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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
        do {
            _ = try AIMemoryStore.add(
                phrase: phrase,
                content: content,
                consent: true,
                in: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
