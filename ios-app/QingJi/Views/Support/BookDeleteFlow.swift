import SwiftUI
import SwiftData
import UIKit

/// 删除账本只解除关联；取消绝不进入更危险的全局删账。
private struct BookDeleteFlow: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var book: Book?

    @State private var emptyTarget: Book?
    @State private var moveTarget: Book?
    @State private var count = 0
    @State private var resultMessage: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: book?.persistentModelID) { _, _ in
                guard let target = book else { return }
                book = nil
                count = BookStore.transactionCount(for: target, in: context)
                if count == 0 {
                    emptyTarget = target
                } else {
                    moveTarget = target
                }
            }
            .appConfirmationDialog(
                "删除「\(emptyTarget?.name ?? "")」？",
                isPresented: presence($emptyTarget),
                message: "只删除这个场景账本及其预算规则，全部账单仍保留在总账本。",
                confirmText: "删除",
                destructive: true
            ) {
                if let target = emptyTarget { run { try BookStore.deleteMovingTransactions(target, in: context) } }
                emptyTarget = nil
            }
            .appConfirmationDialog(
                "「\(moveTarget?.name ?? "")」有 \(count) 笔账目",
                isPresented: presence($moveTarget),
                message: "只移除这个场景账本及其预算规则。账单仍可在总账本和其他已关联的账本查看，账户余额不变。",
                confirmText: "删除账本"
            ) {
                if let target = moveTarget {
                    let moved = count
                    run(success: "已解除 \(moved) 笔账目的关联，原账单已保留") {
                        try BookStore.deleteMovingTransactions(target, in: context)
                    }
                }
                moveTarget = nil
            }
            .alert(
                "删除账本",
                isPresented: Binding(
                    get: { resultMessage != nil },
                    set: { if !$0 { resultMessage = nil } }
                )
            ) {
                Button("好") { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
    }

    private func presence(_ value: Binding<Book?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }

    private func run(success: String? = nil, _ action: () throws -> Void) {
        let message: String?
        do {
            try action()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = success
        } catch {
            message = error.localizedDescription
        }
        guard let message else { return }
        // Confirmation actions already run after their presenter has dismissed.
        resultMessage = message
    }
}

extension View {
    /// 把 `book` 设为要删的账本即开始删除确认流程，流程开始后会自动置回 nil。
    func bookDeleteFlow(_ book: Binding<Book?>) -> some View {
        modifier(BookDeleteFlow(book: book))
    }
}
