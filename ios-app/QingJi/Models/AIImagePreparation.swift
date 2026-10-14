import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Serial, app-private network copies. Originals remain the UI/backup source.
actor AIImagePreparation {
    static let shared = AIImagePreparation()
    private var pending: [String: Task<AIChatAttachment, Error>] = [:]
    private var tail: Task<Void, Never>?

    func prepare(_ attachment: AIChatAttachment) async throws -> AIChatAttachment {
        guard attachment.isImage else {
            guard let data = attachment.data(), !data.isEmpty,
                  data.count <= AIChatAttachmentStore.maxFileBytes else {
                throw AIImagePreparationError.invalidFile
            }
            return attachment
        }
        let key = attachment.metadata.relativePath
        if let task = pending[key] { return try await task.value }
        let previous = tail
        let task = Task.detached(priority: .userInitiated) {
            await previous?.value
            return try Self.makeCopy(attachment)
        }
        tail = Task { _ = try? await task.value }
        pending[key] = task
        defer { pending[key] = nil }
        return try await task.value
    }

    private nonisolated static func makeCopy(_ attachment: AIChatAttachment) throws -> AIChatAttachment {
        guard let url = AttachmentStore.url(for: attachment.metadata.relativePath),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= AIChatAttachmentStore.maxImageBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20000, height <= 20000,
              width * height <= 24 * 1024 * 1024 else {
            throw AIImagePreparationError.invalidImage
        }
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        let type = CGImageSourceGetType(source) as String? ?? ""
        let mime = type == UTType.png.identifier ? "image/png"
            : type == UTType.jpeg.identifier ? "image/jpeg"
            : type == UTType.webP.identifier ? "image/webp"
            : type == UTType.gif.identifier ? "image/gif" : ""
        let edge = mime == "image/png" ? 4096 : 3072
        let resize = max(width, height) > edge
        if !mime.isEmpty && (CGImageSourceGetCount(source) > 1 ||
            (!resize && (size <= 1024 * 1024 || mime != "image/jpeg"))) {
            return AIChatAttachment(metadata: AIChatAttachmentMetadata(id: attachment.id,
                relativePath: attachment.metadata.relativePath, name: attachment.name,
                mimeType: mime, sizeBytes: original.count))
        }
        let key = digest(Data("feimiao-image-v1:\(digest(original))".utf8))
        let parent = url.deletingLastPathComponent().appendingPathComponent(".ai_prepared_v1", isDirectory: true)
        let manifest = parent.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: manifest),
           let record = try? JSONDecoder().decode(CacheRecord.self, from: data),
           record.file == URL(fileURLWithPath: record.file).lastPathComponent {
            let cached = parent.appendingPathComponent(record.file)
            if let bytes = try? Data(contentsOf: cached), bytes.count == record.bytes, digest(bytes) == record.digest {
                return copyMetadata(attachment, filename: record.file, mime: record.mime, bytes: bytes.count)
            }
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(edge, max(width, height)),
        ] as CFDictionary) else { throw AIImagePreparationError.invalidImage }
        let alpha = [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo)
        let lossless = mime == "image/png" || alpha
        let outputMime = lossless ? "image/png" : "image/jpeg"
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, (lossless ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil) else {
            throw AIImagePreparationError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AIImagePreparationError.invalidImage }
        let bytes = output as Data
        guard bytes.count <= AIChatAttachmentStore.maxImageBytes else { throw AIImagePreparationError.invalidImage }
        if !resize && !mime.isEmpty && bytes.count >= original.count {
            return AIChatAttachment(metadata: AIChatAttachmentMetadata(id: attachment.id,
                relativePath: attachment.metadata.relativePath, name: attachment.name,
                mimeType: mime, sizeBytes: original.count))
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let filename = "\(key).\(lossless ? "png" : "jpg")"
        try bytes.write(to: parent.appendingPathComponent(filename), options: .atomic)
        let record = CacheRecord(file: filename, mime: outputMime, bytes: bytes.count, digest: digest(bytes))
        try JSONEncoder().encode(record).write(to: manifest, options: .atomic)
        return copyMetadata(attachment, filename: filename, mime: outputMime, bytes: bytes.count)
    }

    private nonisolated static func copyMetadata(_ original: AIChatAttachment, filename: String, mime: String, bytes: Int) -> AIChatAttachment {
        let parent = (original.metadata.relativePath as NSString).deletingLastPathComponent
        let relative = (parent as NSString).appendingPathComponent(".ai_prepared_v1/\(filename)")
        return AIChatAttachment(metadata: AIChatAttachmentMetadata(id: original.id,
            relativePath: relative, name: original.name, mimeType: mime, sizeBytes: bytes))
    }

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private struct CacheRecord: Codable { let file: String; let mime: String; let bytes: Int; let digest: String }
}

enum AIImagePreparationError: LocalizedError {
    case invalidImage, invalidFile
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片无法读取、超过 20 MB 或像素过大，请调整后重新添加。"
        case .invalidFile: return "附件无法读取、为空或超过 50 MB，请重新添加。"
        }
    }
}
