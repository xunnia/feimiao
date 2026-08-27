import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 存钱目标：把 Android 端的目标金额、已存金额和进度迁移成原生列表。
struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsGoal.updatedAt, order: .reverse)
    private var goals: [SavingsGoal]

    @State private var showEditor = false
    @State private var editingGoal: SavingsGoal?
    @State private var errorMessage: String?

    private var activeGoals: [SavingsGoal] { goals.filter { !$0.isArchived } }
    private var archivedGoals: [SavingsGoal] { goals.filter(\.isArchived) }

    var body: some View {
        List {
            if activeGoals.isEmpty {
                ContentUnavailableView(
                    "还没有存钱目标",
                    systemImage: "target",
                    description: Text("为旅行、设备或应急金设一个目标")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("进行中") {
                    ForEach(activeGoals) { goal in
                        goalRow(goal)
                            .contentShape(Rectangle())
                            .onTapGesture { editingGoal = goal }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    do { try SavingsGoalStore.archive(goal, in: context) }
                                    catch { errorMessage = error.localizedDescription }
                                } label: {
                                    Label("归档", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                    }
                }
            }

            if !archivedGoals.isEmpty {
                Section("已归档") {
                    ForEach(archivedGoals) { goal in
                        goalRow(goal)
                            .foregroundStyle(.secondary)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    do { try SavingsGoalStore.restore(goal, in: context) }
                                    catch { errorMessage = error.localizedDescription }
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.accentColor)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("存钱目标")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建存钱目标")
            }
        }
        .sheet(isPresented: $showEditor) {
            SavingsGoalEditor(goal: nil)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingGoal) { goal in
            SavingsGoalEditor(goal: goal)
                .presentationDetents([.medium, .large])
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

    private func goalRow(_ goal: SavingsGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(goal.emoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name)
                        .font(.body.weight(.medium))
                    Text(goal.isCompleted
                         ? "已达成"
                         : "还差 \(MoneyFormat.string(goal.targetAmount > goal.savedAmount ? goal.targetAmount - goal.savedAmount : .zero, currencyCode: goal.currencyCode))")
                        .font(.caption)
                        .foregroundStyle(goal.isCompleted ? Color.income : .secondary)
                }
                Spacer(minLength: 8)
                Text(MoneyFormat.string(goal.savedAmount, currencyCode: goal.currencyCode))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: goal.progress)
                .tint(goal.isCompleted ? Color.income : Color.accentColor)
            HStack {
                Text("目标 \(MoneyFormat.string(goal.targetAmount, currencyCode: goal.currencyCode))")
                Spacer()
                Text("\(Int(goal.progress * 100))%")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct SavingsGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let goal: SavingsGoal?
    @State private var name: String
    @State private var emoji: String
    @State private var targetText: String
    @State private var savedText: String
    @State private var currencyCode: String
    @State private var note: String
    @State private var errorMessage: String?

    private let emojiChoices = ["🐷", "✈️", "🏠", "🚗", "📱", "🎓", "🎁", "🧰"]

    init(goal: SavingsGoal?) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _emoji = State(initialValue: goal?.emoji ?? "🐷")
        _targetText = State(initialValue: goal.map { "\($0.targetAmount)" } ?? "")
        _savedText = State(initialValue: goal.map { "\($0.savedAmount)" } ?? "0")
        _currencyCode = State(initialValue: goal?.currencyCode ?? "CNY")
        _note = State(initialValue: goal?.note ?? "")
    }

    private var targetAmount: Decimal? { Decimal(string: targetText.replacingOccurrences(of: ",", with: "")) }
    private var savedAmount: Decimal? { Decimal(string: savedText.replacingOccurrences(of: ",", with: "")) }
    private var canSave: Bool {
        guard let targetAmount, let savedAmount else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetAmount > 0 && savedAmount >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("目标名称", text: $name)
                    TextField("目标金额", text: $targetText)
                        .keyboardType(.decimalPad)
                    TextField("已存金额", text: $savedText)
                        .keyboardType(.decimalPad)
                    TextField("币种", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                }
                Section("图标") {
                    HStack(spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { choice in
                            Button { emoji = choice } label: {
                                Text(choice)
                                    .font(.title2)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        emoji == choice ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground),
                                        in: .circle
                                    )
                                    .overlay {
                                        if emoji == choice { Circle().stroke(Color.accentColor, lineWidth: 1.5) }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(goal == nil ? "新建目标" : "编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(goal == nil ? "创建" : "保存") { save() }
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
        guard let targetAmount, let savedAmount, canSave else { return }
        do {
            if let goal {
                try SavingsGoalStore.update(
                    goal,
                    in: context,
                    name: name,
                    emoji: emoji,
                    targetAmount: targetAmount,
                    savedAmount: savedAmount,
                    currencyCode: currencyCode,
                    note: note
                )
            } else {
                _ = try SavingsGoalStore.create(
                    in: context,
                    name: name,
                    emoji: emoji,
                    targetAmount: targetAmount,
                    savedAmount: savedAmount,
                    currencyCode: currencyCode,
                    note: note
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
