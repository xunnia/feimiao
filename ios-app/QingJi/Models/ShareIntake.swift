import Foundation

struct PendingShare {
    let text: String
    let imageFileName: String?
}

/// Main-app side of the Share Extension hand-off. Payloads older than one
/// day are ignored so a stale payment screenshot cannot unexpectedly open later.
enum ShareIntake {
    static let groupID = "group.com.qingji.app"
    static let pendingFileName = "pending-share.json"

    static func consume() -> PendingShare? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return nil }
        let pending = container.appendingPathComponent(pendingFileName)
        guard let data = try? Data(contentsOf: pending),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        try? FileManager.default.removeItem(at: pending)

        let createdAt = object["createdAt"] as? TimeInterval ?? 0
        guard createdAt > 0, Date().timeIntervalSince1970 - createdAt < 86_400 else {
            if let name = object["imageFileName"] as? String { removeImage(name, in: container) }
            return nil
        }
        let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let image = safeFileName(object["imageFileName"] as? String)
        guard !text.isEmpty || image != nil else { return nil }
        return PendingShare(text: text, imageFileName: image)
    }

    static func imageData(for fileName: String) -> Data? {
        guard let safe = safeFileName(fileName),
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupID
              ) else { return nil }
        let url = container.appendingPathComponent(safe)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    private static func safeFileName(_ value: String?) -> String? {
        guard let value, value.count <= 100,
              value == URL(fileURLWithPath: value).lastPathComponent,
              value.hasPrefix("share-"), value.hasSuffix(".jpg") else { return nil }
        return value
    }

    private static func removeImage(_ name: String, in container: URL) {
        guard let safe = safeFileName(name) else { return }
        try? FileManager.default.removeItem(at: container.appendingPathComponent(safe))
    }
}
