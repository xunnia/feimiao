import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// 聊天附件导入：主页 [+] 和喵助手 [+] 共用，限制和提示文案只写这一处。
/// `existing` 是输入框里已有的附件，用来算「最多 3 张图 / 10 个文件」的余量。
@MainActor
enum ChatAttachmentImporter {
    struct Outcome {
        var added: [AIChatAttachment] = []
        var message: String?
    }

    static func importPhotos(_ items: [PhotosPickerItem], existing: [AIChatAttachment]) async -> Outcome {
        var outcome = Outcome()
        let existingImages = existing.filter(\.isImage).count
        for item in items {
            if existingImages + outcome.added.count >= AIChatAttachmentStore.maxImages {
                outcome.message = "一次最多发送 3 张图片。"
                break
            }
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw) else { continue }
            append(image: image, into: &outcome, existingImages: existingImages)
        }
        return outcome
    }

    static func importCamera(_ image: UIImage, existing: [AIChatAttachment]) -> Outcome {
        var outcome = Outcome()
        let existingImages = existing.filter(\.isImage).count
        guard existingImages < AIChatAttachmentStore.maxImages else {
            outcome.message = "一次最多发送 3 张图片。"
            return outcome
        }
        append(image: image, into: &outcome, existingImages: existingImages)
        return outcome
    }

    static func importFiles(_ result: Result<[URL], Error>, existing: [AIChatAttachment]) -> Outcome {
        var outcome = Outcome()
        do {
            let urls = try result.get()
            let room = max(0, AIChatAttachmentStore.maxFiles - existing.filter { !$0.isImage }.count)
            for url in urls.prefix(room) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard !data.isEmpty else { continue }
                if data.count > AIChatAttachmentStore.maxFileBytes {
                    outcome.message = "文件不能超过 50 MB：\(url.lastPathComponent)"
                    continue
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                if let attachment = try? AIChatAttachmentStore.persist(
                    data: data,
                    name: url.lastPathComponent,
                    mimeType: mime
                ) {
                    outcome.added.append(attachment)
                }
            }
            if urls.count > room, outcome.message == nil {
                outcome.message = "一次最多发送 10 个文件。"
            }
        } catch {
            outcome.message = "无法读取附件：\(error.localizedDescription)"
        }
        return outcome
    }

    private static func append(image: UIImage, into outcome: inout Outcome, existingImages: Int) {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        if data.count > AIChatAttachmentStore.maxImageBytes {
            outcome.message = "图片不能超过 20 MB。"
            return
        }
        if let attachment = try? AIChatAttachmentStore.persist(
            data: data,
            name: "支付截图-\(existingImages + outcome.added.count + 1).jpg",
            mimeType: "image/jpeg"
        ) {
            outcome.added.append(attachment)
        }
    }
}

/// 「添加到聊天」面板（对齐安卓 chat_add_sheet.dart）：
/// 顶栏 ✕ / 标题 / 全部照片 → 相机 + 最近照片（多选最多 3 张）→ 添加文件 → 联网搜索。
/// 安卓的「工具权限」一行 iOS 暂不做：iOS 喵助手还没有工具调用。
struct ChatAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 输入框里已有的附件，只用来算余量。
    let existing: [AIChatAttachment]
    /// 选好的附件；面板关闭前回调一次。提示（超限等）一并带回，由调用方弹出。
    let onPicked: ([AIChatAttachment], String?) -> Void

    @AppStorage(ChatWebSearchPreference.key) private var webSearchEnabled = true
    @State private var selection: [PhotosPickerItem] = []
    @State private var showAllPhotos = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var cameraUnavailable = false

    /// 拍照结果先存着，等相机页完全关掉再回调并关面板，避免两个 dismiss 撞在一起。
    @State private var pendingCameraOutcome: ChatAttachmentImporter.Outcome?

    private var remainingImages: Int {
        max(0, AIChatAttachmentStore.maxImages - existing.filter(\.isImage).count)
    }

    /// 系统选择器的 0 表示「不限」，所以至少传 1；没余量时控件本身是禁用的。
    private var pickerLimit: Int { max(1, remainingImages) }

    var body: some View {
        VStack(spacing: 14) {
            header
            photoStrip
            if !selection.isEmpty {
                addPhotosButton
            }
            card {
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .frame(width: 28)
                        Text("添加文件")
                            .font(.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            card {
                Toggle(isOn: $webSearchEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("联网搜索")
                                .font(.body)
                            Text("需要查最新信息时，喵助手可以上网搜索")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 44)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .disabled(isImporting)
        .overlay {
            if isImporting {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .photosPicker(
            isPresented: $showAllPhotos,
            selection: $selection,
            maxSelectionCount: pickerLimit,
            selectionBehavior: .ordered,
            matching: .images
        )
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let outcome = pendingCameraOutcome {
                pendingCameraOutcome = nil
                finish(outcome)
            }
        }) {
            CameraImagePicker { image in
                pendingCameraOutcome = ChatAttachmentImporter.importCamera(image, existing: existing)
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            finish(ChatAttachmentImporter.importFiles(result, existing: existing))
        }
        .alert("当前设备没有可用相机", isPresented: $cameraUnavailable) {
            Button("好", role: .cancel) {}
        }
    }

    private var header: some View {
        ZStack {
            Text("添加到聊天")
                .font(.headline)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .liquidGlassCircleControl(size: 44)
                .accessibilityLabel("关闭")

                Spacer()

                Button {
                    showAllPhotos = true
                } label: {
                    Text("全部照片")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .liquidGlassPillControl(horizontalPadding: 14)
                .disabled(remainingImages == 0)
            }
        }
    }

    /// 相机格 + 系统照片选择器的内嵌横条（按选择顺序编号，最多 3 张）。
    private var photoStrip: some View {
        HStack(spacing: 8) {
            Button {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    cameraUnavailable = true
                    return
                }
                showCamera = true
            } label: {
                Image(systemName: "camera")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 94, height: 94)
                    .background(Color(uiColor: .secondarySystemFill), in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(remainingImages == 0)
            .accessibilityLabel("拍照")

            PhotosPicker(
                selection: $selection,
                maxSelectionCount: pickerLimit,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Text("选择照片")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities([.search, .collectionNavigation, .stagingArea, .selectionActions])
            .photosPickerAccessoryVisibility(.hidden, edges: .all)
            .photosPickerAxes(.horizontal)
            .frame(height: 94)
            .clipShape(.rect(cornerRadius: 18))
            .disabled(remainingImages == 0)
        }
        .frame(height: 94)
    }

    private var addPhotosButton: some View {
        Button {
            let items = selection
            isImporting = true
            Task { @MainActor in
                let outcome = await ChatAttachmentImporter.importPhotos(items, existing: existing)
                isImporting = false
                finish(outcome)
            }
        } label: {
            Text("添加 \(selection.count) 张照片")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .liquidGlassPrimaryPillControl(minHeight: 50)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func finish(_ outcome: ChatAttachmentImporter.Outcome) {
        guard !outcome.added.isEmpty || outcome.message != nil else { return }
        onPicked(outcome.added, outcome.message)
        dismiss()
    }
}
