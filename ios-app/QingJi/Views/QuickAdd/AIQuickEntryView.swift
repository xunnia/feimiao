import UIKit
import SwiftUI
import SwiftData
import PhotosUI
import Vision
import QingJiCore

/// AI 记一笔：一句话 / 语音 / 支付截图 OCR 三种方式入账。
/// 当前用本地规则解析（零网络、保隐私），后续可无缝换成云端大模型。
struct AIQuickEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var text = ""
    @State private var parsed: ParsedEntry?
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognizingImage = false
    @State private var speech = SpeechDictation()

    var body: some View {
        NavigationStack {
            Form {
                Section("一句话记账") {
                    TextField("例如：昨天打车23块", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                        .onSubmit(parseText)
                    HStack(spacing: 20) {
                        Button {
                            speech.toggle()
                        } label: {
                            Label(
                                speech.isRecording ? "停止" : "语音",
                                systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill"
                            )
                        }
                        .tint(speech.isRecording ? .red : .accentColor)

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("支付截图", systemImage: "photo.on.rectangle")
                        }

                        Spacer()

                        Button("解析", action: parseText)
                            .buttonStyle(.glassProminent)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if isRecognizingImage {
                        HStack {
                            ProgressView()
                            Text("正在识别截图…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let message = speech.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let parsed {
                    Section("识别结果") {
                        LabeledContent("类型") {
                            Text(parsed.kind == .income ? "收入" : "支出")
                        }
                        LabeledContent("金额") {
                            Text(parsed.amount.map { "\($0)" } ?? "未识别")
                                .foregroundStyle(parsed.amount == nil ? Color.red : Color.primary)
                        }
                        LabeledContent("分类") {
                            Text(matchedCategory(for: parsed)?.name ?? "其他")
                        }
                        LabeledContent("日期") {
                            Text(parsed.date, format: .dateTime.month().day())
                        }
                        Button("保存这笔") {
                            save(parsed)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(parsed.amount == nil)
                    }
                }
            }
            .navigationTitle("AI 记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        speech.stop()
                        dismiss()
                    }
                }
            }
            .onChange(of: speech.transcript) {
                guard !speech.transcript.isEmpty else { return }
                text = speech.transcript
                parseText()
            }
            .onChange(of: photoItem) {
                recognizeSelectedImage()
            }
            .onDisappear {
                speech.stop()
            }
        }
    }

    private func parseText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parsed = NaturalLanguageEntryParser.parse(trimmed)
    }

    private func matchedCategory(for parsed: ParsedEntry) -> TxCategory? {
        if let key = parsed.categoryKey,
           let match = categories.first(where: { $0.key == key }) {
            return match
        }
        let fallbackKey = parsed.kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
        return categories.first { $0.key == fallbackKey }
    }

    private func save(_ parsed: ParsedEntry) {
        guard let amount = parsed.amount, amount > 0 else { return }
        let account = accounts.first
        context.insert(MoneyTransaction(
            amount: amount,
            kind: parsed.kind,
            date: parsed.date,
            note: parsed.note,
            currencyCode: account?.currencyCode ?? "CNY",
            category: matchedCategory(for: parsed),
            account: account
        ))
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        speech.stop()
        dismiss()
    }

    /// 截图 → Vision OCR → 金额提取 + 文本回填。
    private func recognizeSelectedImage() {
        guard let photoItem else { return }
        isRecognizingImage = true
        Task {
            defer { isRecognizingImage = false }
            guard let data = try? await photoItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else { return }

            var request = RecognizeTextRequest()
            request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
            guard let observations = try? await request.perform(on: cgImage) else { return }
            let ocrText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            guard !ocrText.isEmpty else { return }

            var entry = NaturalLanguageEntryParser.parse(ocrText)
            entry.amount = PaymentScreenshotParser.extractAmount(fromOCRText: ocrText) ?? entry.amount
            // 备注取 OCR 的前两行（一般是「支付成功」和商户名），全文太长
            entry.note = ocrText.split(separator: "\n").prefix(2).joined(separator: " ")
            text = entry.note
            parsed = entry
        }
    }
}
