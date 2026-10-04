import XCTest
import UIKit
@testable import QingJi

final class AIImagePreparationTests: XCTestCase {
    func testSmallScreenshotKeepsOriginalBytesAndMetadata() async throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 180)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 180))
            ("Invoice 128.56" as NSString).draw(at: CGPoint(x: 8, y: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black])
        }
        let original = try AIChatAttachmentStore.persist(data: data, name: "invoice.png", mimeType: "image/png")
        defer { if let url = AttachmentStore.url(for: original.metadata.relativePath) { try? FileManager.default.removeItem(at: url) } }
        let prepared = try await AIImagePreparation.shared.prepare(original)
        XCTAssertEqual(prepared.metadata, original.metadata)
        XCTAssertEqual(prepared.data(), data)
        XCTAssertEqual(original.data(), data)
    }

    func testSummaryPreservesWhitespaceAndBoundsMemory() {
        var summary = AIStreamSummaryBuffer()
        summary.append("**范围**"); summary.append("\n\n"); summary.append(String(repeating: "内容", count: 500))
        XCTAssertTrue(summary.text.hasPrefix("**范围**\n\n"))
        XCTAssertGreaterThan(summary.text.count, 420)
        summary.append(String(repeating: "x", count: 70000))
        XCTAssertEqual(summary.text.count, AIStreamSummaryBuffer.maxCharacters)
        XCTAssertTrue(summary.truncated)
        XCTAssertEqual(summary.append("不应添加"), "")
    }

    func testSummaryManySmallDeltasKeepParagraphsAndRespectTheSameLimit() {
        var summary = AIStreamSummaryBuffer()
        var expected = ""
        for index in 0..<3000 {
            let delta = index.isMultiple(of: 7) ? "\n\n" : "增量摘要"
            XCTAssertEqual(summary.append(delta), delta)
            expected += delta
        }
        XCTAssertEqual(summary.text, expected)
        XCTAssertFalse(summary.truncated)
        summary.append(String(repeating: "尾", count: AIStreamSummaryBuffer.maxCharacters))
        XCTAssertEqual(summary.text.count, AIStreamSummaryBuffer.maxCharacters)
        XCTAssertTrue(summary.truncated)
    }

    func testImageContentDeterminesMIMEWithoutChangingTheOriginal() async throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let original = try AIChatAttachmentStore.persist(data: data, name: "renamed.jpg", mimeType: "image/jpeg")
        defer { if let url = AttachmentStore.url(for: original.metadata.relativePath) { try? FileManager.default.removeItem(at: url) } }
        let prepared = try await AIImagePreparation.shared.prepare(original)
        XCTAssertEqual(prepared.mimeType, "image/png")
        XCTAssertEqual(prepared.metadata.relativePath, original.metadata.relativePath)
        XCTAssertEqual(prepared.data(), data)
        XCTAssertEqual(original.mimeType, "image/jpeg")
        XCTAssertEqual(original.data(), data)
    }

    func testInvalidImageDoesNotBecomeAPlaceholderRequest() async throws {
        let image = try AIChatAttachmentStore.persist(data: Data([1, 2, 3]), name: "bad.png", mimeType: "image/png")
        defer { if let url = AttachmentStore.url(for: image.metadata.relativePath) { try? FileManager.default.removeItem(at: url) } }
        do {
            _ = try await AIImagePreparation.shared.prepare(image)
            XCTFail("Corrupt image must not reach the provider")
        } catch { XCTAssertTrue(error is AIImagePreparationError) }
    }
}
