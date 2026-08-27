import Foundation

/// Persisted metadata for one chat attachment. The bytes live under the
/// app-owned attachment directory and are never embedded in chat JSON.
struct AIChatAttachmentMetadata: Codable, Hashable, Sendable {
    let id: UUID
    let relativePath: String
    let name: String
    let mimeType: String
    let sizeBytes: Int

    var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
}

/// A message attachment that can be rendered locally and loaded by the AI
/// request layer. Metadata is value-semantic so restored messages are safe to
/// pass through SwiftUI state.
struct AIChatAttachment: Identifiable, Hashable, Sendable {
    let metadata: AIChatAttachmentMetadata

    var id: UUID { metadata.id }
    var name: String { metadata.name }
    var mimeType: String { metadata.mimeType }
    var isImage: Bool { metadata.isImage }
    var sizeBytes: Int { metadata.sizeBytes }

    func data() -> Data? {
        guard let url = AttachmentStore.url(for: metadata.relativePath) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

enum AIChatAttachmentStore {
    static let maxImages = 3
    static let maxFiles = 10
    static let maxImageBytes = 20 * 1024 * 1024
    static let maxFileBytes = 50 * 1024 * 1024

    static func persist(data: Data, name: String, mimeType: String) throws -> AIChatAttachment {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty ? "附件" : trimmedName
        let fileExtension = URL(fileURLWithPath: safeName).pathExtension.isEmpty
            ? extensionFor(mimeType: mimeType)
            : URL(fileURLWithPath: safeName).pathExtension
        let relativePath = try AttachmentStore.save(data: data, fileExtension: fileExtension)
        return AIChatAttachment(metadata: AIChatAttachmentMetadata(
            id: UUID(),
            relativePath: relativePath,
            name: safeName,
            mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType,
            sizeBytes: data.count
        ))
    }

    static func restore(_ metadata: AIChatAttachmentMetadata) -> AIChatAttachment? {
        guard AttachmentStore.url(for: metadata.relativePath) != nil,
              let data = AIChatAttachment(metadata: metadata).data(),
              !data.isEmpty else { return nil }
        return AIChatAttachment(metadata: metadata)
    }

    static func encode(_ attachments: [AIChatAttachment]) -> String {
        guard let data = try? JSONEncoder().encode(attachments.map(\.metadata)) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ raw: String) -> [AIChatAttachmentMetadata] {
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([AIChatAttachmentMetadata].self, from: data) else {
            return []
        }
        return values
    }

    private static func extensionFor(mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        case "application/json": return "json"
        default: return "bin"
        }
    }
}
