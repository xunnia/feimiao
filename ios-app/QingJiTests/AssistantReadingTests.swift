import XCTest
import SwiftUI
import UIKit
@testable import QingJi

final class AssistantReadingTests: XCTestCase {
    func testOnlyWebLinksMayBeOpenedFromModelOutput() throws {
        for value in ["https://example.com", "http://localhost:1455/path"] {
            XCTAssertTrue(AssistantReadingPolicy.isWebURL(try XCTUnwrap(URL(string: value))))
        }
        for value in ["file:///private/data", "qingji://delete", "javascript:alert(1)", "https:/missing-host"] {
            XCTAssertFalse(AssistantReadingPolicy.isWebURL(try XCTUnwrap(URL(string: value))))
        }
    }

    func testMessageTimestampIsExplicitAndStableAcrossTextUpdates() {
        let date = Date(timeIntervalSince1970: 1_791_100_800)
        let original = AIChatTurn(role: "assistant", content: "第一段", createdAt: date)
        let updated = AIChatTurn(id: original.id, role: original.role,
                                 content: original.content + "第二段",
                                 attachments: original.attachments, createdAt: original.createdAt)
        XCTAssertEqual(updated.createdAt, date)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, "第一段第二段")
    }

    @MainActor
    func testCaptureReadingComponentsForNativeReview() async throws {
        let fixtures: [(String, ColorScheme, CGFloat, UIContentSizeCategory)] = [
            ("warm", .light, 420, .large), ("night", .dark, 420, .large),
            ("narrow-large", .light, 320, .accessibilityExtraExtraLarge),
        ]
        for (name, scheme, width, size) in fixtures {
            try await attach(name: "chat-reading-\(name)", scheme: scheme, width: width, size: size,
                view: ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        AssistantThinkingSummary(summary: "核对用户的偏好并整理三个简短安排。", seconds: 12)
                        AssistantMarkdownBody(text: """
                        ## 周末安排

                        先留出休息时间，再安排 **两件小事**。

                        1. 上午沿着熟悉的路线散步，遇到喜欢的小店可以停一会儿。
                        2. 午后读书，不设完成任务。

                        > 不必把每段空闲都安排满。

                        | 安排 | 时间 | 注意事项 |
                        | --- | ---: | --- |
                        | 散步 | 40 分钟 | 选熟悉的路线，途中可以停下来休息 |

                        ```text
                        周六：散步、看书
                        周日：留给自己
                        ```
                        """)
                        AssistantSourcesButton(sources: sources)
                    }.padding(16)
                }.liquidGlassCanvas())
        }
    }

    @MainActor
    func testCaptureSourcesForNativeReview() async throws {
        try await attach(name: "chat-sources", scheme: .light, width: 420, size: .large,
                         view: AssistantSourcesSheet(sources: sources))
    }

    private var sources: [AIChatSource] { [
        AIChatSource(title: "周末安排", url: "https://example.com/weekend", snippet: "开放时间与交通信息"),
        AIChatSource(title: "开放时间", url: "https://example.org/hours", snippet: ""),
    ] }

    @MainActor
    private func attach<Content: View>(name: String, scheme: ColorScheme, width: CGFloat,
                                      size: UIContentSizeCategory, view: Content) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 912)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.traitOverrides.preferredContentSizeCategory = size
        let controller = UIHostingController(rootView: view.environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "zh-Hans")))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
