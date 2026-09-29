import SwiftUI
import SwiftData
import UIKit

/// 删账本的三段确认，对齐安卓 `_confirmDeleteBook`：
/// 没账目 → 确认删除；有账目 → 先推荐「转移并删除」；
/// 用户拒绝转移 → 再弹一次「永久删除」，连账目一起删。
private struct BookDeleteFlow: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var book: Book?

    @State private var emptyTarget: Book?
    @State private var moveTarget: Book?
    @State private var wipeTarget: Book?
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
            .alert(
                "删除「\(emptyTarget?.name ?? "")」？",
                isPresented: presence($emptyTarget)
            ) {
                Button("删除", role: .destructive) {
                    if let target = emptyTarget { run { try BookStore.deleteMovingTransactions(target, in: context) } }
                    emptyTarget = nil
                }
                Button("取消", role: .cancel) { emptyTarget = nil }
            } message: {
                Text("这个账本没有账目，删除后不可恢复。")
            }
            .alert(
                "「\(moveTarget?.name ?? "")」有 \(count) 笔账目",
                isPresented: presence($moveTarget)
            ) {
                Button("转移并删除") {
                    if let target = moveTarget {
                        let moved = count
                        run(success: "\(moved) 笔账目已转移到总账本") {
                            try BookStore.deleteMovingTransactions(target, in: context)
                        }
                    }
                    moveTarget = nil
                }
                Button("取消", role: .cancel) {
                    let target = moveTarget
                    moveTarget = nil
                    // 等上一个弹窗收起再弹第二道确认，否则 SwiftUI 会吞掉这一次展示。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        wipeTarget = target
                    }
                }
            } message: {
                Text("建议把账目转移到总账本再删——记录一笔不丢。\n（点「取消」后仍想连账目一起删，会有单独确认。）")
            }
            .alert(
                "连 \(count) 笔账目一起删除？",
                isPresented: presence($wipeTarget)
            ) {
                Button("永久删除", role: .destructive) {
                    if let target = wipeTarget { run { try BookStore.deleteWithTransactions(target, in: context) } }
                    wipeTarget = nil
                }
                Button("取消", role: .cancel) { wipeTarget = nil }
            } message: {
                Text("「\(wipeTarget?.name ?? "")」和它的全部账目将永久删除，无法恢复。")
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
        // 同样等确认弹窗收起后再提示结果。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            resultMessage = message
        }
    }
}

extension View {
    /// 把 `book` 设为要删的账本即开始删除确认流程，流程开始后会自动置回 nil。
    func bookDeleteFlow(_ book: Binding<Book?>) -> some View {
        modifier(BookDeleteFlow(book: book))
    }
}
