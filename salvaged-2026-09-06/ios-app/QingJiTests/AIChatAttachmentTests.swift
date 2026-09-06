import XCTest
@testable import QingJi

final class AIChatAttachmentTests: XCTestCase {
    private func attachment(_ id: UUID, mimeType: String) -> AIChatAttachment {
        AIChatAttachment(metadata: AIChatAttachmentMetadata(
            id: id,
            relativePath: "chat/\(id.uuidString).bin",
            name: "附件",
            mimeType: mimeType,
            sizeBytes: 1
        ))
    }

    func testCapacityIsTrackedSeparatelyForImagesAndFiles() {
        let images = (0..<2).map { _ in attachment(UUID(), mimeType: "image/jpeg") }
        XCTAssertTrue(AIChatAttachmentStore.hasCapacity(for: "image/png", existing: images))
        XCTAssertFalse(
            AIChatAttachmentStore.hasCapacity(
                for: "image/png",
                existing: images + [attachment(UUID(), mimeType: "image/jpeg")]
            )
        )

        let files = (0..<9).map { _ in attachment(UUID(), mimeType: "application/pdf") }
        XCTAssertTrue(AIChatAttachmentStore.hasCapacity(for: "text/plain", existing: files))
        XCTAssertFalse(
            AIChatAttachmentStore.hasCapacity(
                for: "text/plain",
                existing: files + [attachment(UUID(), mimeType: "application/pdf")]
            )
        )
    }

    func testImageAndFileSlotsDoNotBlockEachOther() {
        let images = (0..<3).map { _ in attachment(UUID(), mimeType: "image/jpeg") }
        XCTAssertTrue(AIChatAttachmentStore.hasCapacity(for: "application/pdf", existing: images))

        let files = (0..<10).map { _ in attachment(UUID(), mimeType: "application/pdf") }
        XCTAssertTrue(AIChatAttachmentStore.hasCapacity(for: "image/jpeg", existing: files))
    }

    func testDraftFilesAreRetainedWhileAnOverlayOrSendIsActive() {
        XCTAssertFalse(
            AIChatAttachmentStore.canDiscardDraftAttachments(
                pendingConsent: true,
                photoPickerPresented: false,
                fileImporterPresented: false,
                preservingForSend: false
            )
        )
        XCTAssertFalse(
            AIChatAttachmentStore.canDiscardDraftAttachments(
                pendingConsent: false,
                photoPickerPresented: true,
                fileImporterPresented: false,
                preservingForSend: false
            )
        )
        XCTAssertFalse(
            AIChatAttachmentStore.canDiscardDraftAttachments(
                pendingConsent: false,
                photoPickerPresented: false,
                fileImporterPresented: true,
                preservingForSend: false
            )
        )
        XCTAssertFalse(
            AIChatAttachmentStore.canDiscardDraftAttachments(
                pendingConsent: false,
                photoPickerPresented: false,
                fileImporterPresented: false,
                preservingForSend: true
            )
        )
        XCTAssertTrue(
            AIChatAttachmentStore.canDiscardDraftAttachments(
                pendingConsent: false,
                photoPickerPresented: false,
                fileImporterPresented: false,
                preservingForSend: false
            )
        )
    }
}
