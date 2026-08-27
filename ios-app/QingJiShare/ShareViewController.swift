import Social
import UniformTypeIdentifiers
import UIKit

/// Receives text or one image from the system share sheet and leaves a small,
/// validated hand-off in the App Group container for the main app.
final class ShareViewController: SLComposeServiceViewController {
    private let groupID = "group.com.qingji.app"

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        Task { @MainActor in
            await saveIncomingItems()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        validateContent()
    }

    override func configurationItems() -> [Any]! { [] }

    private func saveIncomingItems() async {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return }

        var text = contentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var imagePath: String?
        let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if text.isEmpty,
                   provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
                   let data = await loadData(provider, type: UTType.text.identifier),
                   let decoded = String(data: data, encoding: .utf8) {
                    text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if imagePath == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let data = await loadData(provider, type: UTType.image.identifier),
                   UIImage(data: data) != nil {
                    let name = "share-\(UUID().uuidString).jpg"
                    let url = container.appendingPathComponent(name)
                    if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9),
                       (try? jpeg.write(to: url, options: .atomic)) != nil {
                        imagePath = name
                    }
                }
            }
        }

        guard !text.isEmpty || imagePath != nil else { return }
        var payload: [String: Any] = [
            "text": text,
            "createdAt": Date().timeIntervalSince1970,
        ]
        if let imagePath { payload["imageFileName"] = imagePath }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        let pending = container.appendingPathComponent("pending-share.json")
        try? data.write(to: pending, options: .atomic)
    }

    private func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
