import XCTest
import SwiftUI
import UIKit
@testable import QingJi

final class ThemePopupPresentationTests: XCTestCase {
    func testColoredSheetsUseActualThemeTintAtEveryIntensity() {
        for preset in [AppThemePreset.warm, .pink, .mint, .blue] {
            for intensity in [0.0, 0.6, 1.0] {
                let theme = palette(preset, intensity: intensity)
                let expected = blend(preset.bottom, preset.top, amount: intensity * 0.35)
                assertColor(theme.sheet, equals: expected)
                XCTAssertNotEqual(UIColor(theme.fill), UIColor(theme.sheet), preset.rawValue)
            }
            XCTAssertNotEqual(UIColor(palette(preset, intensity: 1).sheet), preset.bottom)
        }
    }

    func testWhiteSheetsStayWhiteAndAllDarkSheetsStayDark() {
        assertColor(palette(.white).sheet, equals: .white)
        for preset in AppThemePreset.allCases {
            let theme = palette(preset, scheme: .dark)
            let base = AppThemePreset.color(preset == .night ? 0x17191F : 0x211E1C)
            assertColor(theme.sheet, equals: blend(base, .white, amount: 0.06))
            XCTAssertTrue(theme.isDark)
        }
        XCTAssertTrue(palette(.night, scheme: .light).isDark)
    }

    func testPopupReadabilityDoesNotDependOnSavedCardOpacity() {
        for preset in AppThemePreset.allCases {
            let low = palette(preset, cardAlpha: 0.25)
            let high = palette(preset, cardAlpha: 0.9)
            assertColor(low.sheet, equals: UIColor(high.sheet))
            assertColor(low.fill, equals: UIColor(high.fill))
        }
    }

    @MainActor
    func testConfirmationUsesNativeAlertActionsAndSafeDestructiveDefault() {
        let controller = nativeDialog(destructive: true, scheme: .light)
        XCTAssertEqual(controller.preferredStyle, .alert)
        XCTAssertEqual(controller.actions.map(\.title), ["取消", "删除"])
        XCTAssertEqual(controller.actions.map(\.style), [.cancel, .default])
        XCTAssertTrue(controller.preferredAction === controller.actions[0])
        XCTAssertEqual(controller.view.tintColor, UIColor(Color.warning))
        XCTAssertEqual(controller.view.accessibilityIdentifier, "app-confirmation-dialog")
    }

    @MainActor
    func testOrdinaryConfirmationKeepsBrandTintAndConfirmAsDefault() {
        let controller = nativeDialog(destructive: false, scheme: .light)
        XCTAssertTrue(controller.preferredAction === controller.actions[1])
        XCTAssertEqual(controller.view.tintColor, UIColor(Color.statisticsAccent))
        XCTAssertEqual(controller.overrideUserInterfaceStyle, .light)
    }

    @MainActor
    func testNativeAppearanceAndMessageUpdateWithoutReplacingActions() {
        let controller = nativeDialog(destructive: true, scheme: .light)
        let originalActions = controller.actions
        AppNativeConfirmation.update(controller, title: "改日常预算", message: "", destructive: false,
                                     colorScheme: .dark)
        XCTAssertEqual(controller.title, "改日常预算")
        XCTAssertNil(controller.message)
        XCTAssertEqual(controller.overrideUserInterfaceStyle, .dark)
        XCTAssertTrue(controller.actions[0] === originalActions[0])
        XCTAssertTrue(controller.actions[1] === originalActions[1])
        XCTAssertTrue(controller.preferredAction === controller.actions[1])
    }

    @MainActor
    func testCaptureNativeThemeConfirmationsForVisualReview() async throws {
        for preset in AppThemePreset.allCases {
            let scheme: ColorScheme = preset == .night ? .dark : .light
            try await attachDialog(palette(preset, scheme: scheme), name: "confirmation-\(preset.rawValue)-delete")
            try await attachDialog(palette(preset, scheme: scheme), name: "confirmation-\(preset.rawValue)-ordinary",
                                   destructive: false)
        }
        try await attachDialog(palette(.warm, scheme: .dark), name: "confirmation-warm-dark")
        try await attachDialog(palette(.pink), name: "confirmation-pink-320-large", width: 320,
                               contentSize: .accessibilityExtraExtraLarge)
    }

    @MainActor
    func testCaptureNativeFormsWithEveryThemeForVisualReview() async throws {
        for preset in AppThemePreset.allCases {
            try await attachForm(palette(preset, scheme: preset == .night ? .dark : .light),
                                 name: "form-\(preset.rawValue)")
        }
        try await attachForm(palette(.warm, scheme: .dark), name: "form-warm-dark")
        try await attachForm(palette(.pink), name: "form-pink-320-large", width: 320,
                             contentSize: .accessibilityExtraExtraLarge)
    }

    private func palette(_ preset: AppThemePreset, scheme: ColorScheme = .light,
                         intensity: Double = 1, cardAlpha: Double = 0.8) -> AppThemePalette {
        AppThemePalette(preferences: AppThemePreferences(presetKey: preset.rawValue,
                                                        intensity: intensity, cardAlpha: cardAlpha),
                        colorScheme: scheme)
    }

    @MainActor
    private func attachDialog(_ theme: AppThemePalette, name: String, width: CGFloat = 420,
                              destructive: Bool = true, contentSize: UIContentSizeCategory = .large) async throws {
        let dialog = AppNativeConfirmation.makeController(
            title: destructive ? "删除这条预算规则？" : "改日常预算",
            message: destructive ? "这几天会回到日常预算，已经记录的账单不会改变。"
                : "这次修改会调整五月以来的预算，已记录的账单不变。",
            confirmText: destructive ? "删除" : "改", cancelText: "取消",
            destructive: destructive, colorScheme: theme.isDark ? .dark : .light,
            onCancel: {}, onConfirm: {})
        try await attachPresentation(theme, name: name, width: width, contentSize: contentSize,
                                     root: LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                                                          startPoint: .top, endPoint: .bottom).ignoresSafeArea(), dialog: dialog)
    }

    @MainActor
    private func attachForm(_ theme: AppThemePalette, name: String, width: CGFloat = 420,
                            contentSize: UIContentSizeCategory = .large) async throws {
        let defaults = UserDefaults.standard
        let saved = ["qingji.themePreset", "qingji.themeIntensity", "qingji.themeCardAlpha"]
            .map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(theme.preferences.preset.rawValue, forKey: "qingji.themePreset")
        defaults.set(theme.preferences.intensity, forKey: "qingji.themeIntensity")
        defaults.set(theme.preferences.cardAlpha, forKey: "qingji.themeCardAlpha")
        let root = NavigationStack {
            AppThemedForm {
                Section("基本信息") {
                    TextField("账户名称", text: .constant("日常账户"))
                    TextField("期初余额", text: .constant("1000.00"))
                        .keyboardType(.decimalPad)
                }
                Section("归属") {
                    Toggle("计入净资产", isOn: .constant(true))
                    Picker("类型", selection: .constant("bank")) {
                        Text("银行卡").tag("bank")
                        Text("现金").tag("cash")
                    }
                }
            }
            .navigationTitle("新增账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    LiquidGlassIconButton(systemName: "xmark", accessibilityLabel: "取消", size: 36) {}
                }
                ToolbarItem(placement: .confirmationAction) {
                    LiquidGlassPillButton("保存") {}
                }
            }
        }
        try await attachPresentation(theme, name: name, width: width, contentSize: contentSize, root: root)
    }

    @MainActor
    private func attachPresentation<Content: View>(_ theme: AppThemePalette, name: String, width: CGFloat,
                                                  contentSize: UIContentSizeCategory, root: Content,
                                                  dialog: UIAlertController? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 912)
        window.overrideUserInterfaceStyle = theme.isDark ? .dark : .light
        window.traitOverrides.preferredContentSizeCategory = contentSize
        let content = root.environment(\.colorScheme, theme.isDark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
        let controller = CaptureHostingController(rootView: content)
        let presenter = UIViewController()
        window.rootViewController = presenter
        controller.modalPresentationStyle = .fullScreen
        controller.view.backgroundColor = UIColor(theme.backgroundBottom)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        var captureError: Error?
        do {
            try await waitUntil(name: name, phase: "window appearance") {
                presenter.view.window === window && presenter.transitionCoordinator == nil
            }
            var presentationCompleted = false
            presenter.present(controller, animated: false) { presentationCompleted = true }
            try await waitUntil(name: name, phase: "host appearance") {
                presentationCompleted && controller.isVisible && controller.view.window === window
                    && !controller.isBeingPresented && controller.transitionCoordinator == nil
            }
            if let dialog {
                var presentationCompleted = false
                controller.present(dialog, animated: false) { presentationCompleted = true }
                try await waitUntil(name: name, phase: "dialog presentation") {
                    presentationCompleted && controller.presentedViewController === dialog
                        && dialog.view.window === window && !dialog.isBeingPresented
                        && dialog.transitionCoordinator == nil
                }
            }
            controller.view.layoutIfNeeded()
            dialog?.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            XCTAssertEqual(image.size.width, width)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            captureError = error
        }
        do {
            try await closeCapture(controller, window: window, name: name)
        } catch {
            if let captureError { throw captureError }
            throw error
        }
        if let captureError { throw captureError }
    }

    @MainActor
    private func closeCapture<Content: View>(_ controller: CaptureHostingController<Content>,
                                             window: UIWindow, name: String) async throws {
        if let dialog = controller.presentedViewController {
            var dismissalCompleted = false
            controller.dismiss(animated: false) { dismissalCompleted = true }
            try await waitUntil(name: name, phase: "dialog dismissal") {
                dismissalCompleted && controller.presentedViewController == nil
                    && dialog.presentingViewController == nil && !dialog.isBeingDismissed
                    && dialog.transitionCoordinator == nil
            }
        }
        try await waitUntil(name: name, phase: "host before removal") {
            controller.isVisible && controller.transitionCoordinator == nil
        }
        // Hiding a root window does not guarantee viewDidDisappear on iOS 26.
        if let presenter = controller.presentingViewController {
            var dismissalCompleted = false
            presenter.dismiss(animated: false) { dismissalCompleted = true }
            try await waitUntil(name: name, phase: "host dismissal") {
                dismissalCompleted && presenter.presentedViewController == nil && controller.presentingViewController == nil
                    && !controller.isVisible && !controller.isBeingDismissed && controller.transitionCoordinator == nil
            }
        }
        try await waitUntil(name: name, phase: "host disappearance") {
            !controller.isVisible && controller.transitionCoordinator == nil
        }
        window.isHidden = true
        window.rootViewController = nil
    }

    @MainActor
    private func waitUntil(name: String, phase: String, timeout: TimeInterval = 5,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "\(name): native view did not become ready for \(phase)", file: file, line: line)
        guard condition() else { throw CaptureError.presentationNotReady }
    }

    private enum CaptureError: Error { case presentationNotReady }

    @MainActor
    private final class CaptureHostingController<Content: View>: UIHostingController<Content> {
        private(set) var isVisible = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            isVisible = false
        }
    }

    @MainActor
    private func nativeDialog(destructive: Bool, scheme: ColorScheme) -> UIAlertController {
        AppNativeConfirmation.makeController(title: "删除这条预算规则？", message: "已记录的账单不变。",
                                             confirmText: "删除", cancelText: "取消", destructive: destructive,
                                             colorScheme: scheme, onCancel: {}, onConfirm: {})
    }

    private func blend(_ from: UIColor, _ to: UIColor, amount: Double) -> UIColor {
        let lhs = components(from)
        let rhs = components(to)
        let fraction = CGFloat(amount)
        return UIColor(red: lhs.0 + (rhs.0 - lhs.0) * fraction,
                       green: lhs.1 + (rhs.1 - lhs.1) * fraction,
                       blue: lhs.2 + (rhs.2 - lhs.2) * fraction, alpha: 1)
    }

    private func assertColor(_ actual: Color, equals expected: UIColor,
                             file: StaticString = #filePath, line: UInt = #line) {
        let lhs = components(UIColor(actual))
        let rhs = components(expected)
        XCTAssertEqual(lhs.0, rhs.0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.1, rhs.1, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.2, rhs.2, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.3, rhs.3, accuracy: 0.001, file: file, line: line)
    }

    private func components(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        return (r, g, b, a)
    }
}
