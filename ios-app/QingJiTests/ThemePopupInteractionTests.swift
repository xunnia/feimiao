import XCTest
import SwiftUI
import UIKit
@testable import QingJi

@MainActor
final class ThemePopupInteractionTests: XCTestCase {
    func testRepeatedConfirmationConsumesPayloadOnceBeforeClearingIt() async throws {
        let session = try await makeSession()
        XCTAssertNotNil(session.coordinator.host)
        session.coordinator.confirm()
        session.coordinator.confirm()
        try await waitUntil { !session.state.presented && session.coordinator.host == nil }
        XCTAssertEqual(session.state.confirmedPayloads, ["budget-rule"])
        XCTAssertNil(session.state.payload)
        XCTAssertFalse(session.state.presented)
        XCTAssertNil(session.coordinator.host)
    }

    func testProgrammaticDismissalDoesNotExecuteTheExplicitCancelAction() async throws {
        let session = try await makeSession()
        session.coordinator.dismissWithoutAction()
        try await waitUntil { !session.state.presented && session.coordinator.host == nil }
        XCTAssertEqual(session.state.cancelCount, 0)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertFalse(session.state.presented)
    }

    func testCancelExecutesOnlyTheCancelAction() async throws {
        let session = try await makeSession()
        session.coordinator.cancel()
        session.coordinator.cancel()
        try await waitUntil { !session.state.presented && session.coordinator.host == nil }
        XCTAssertEqual(session.state.cancelCount, 1)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertFalse(session.state.presented)
    }

    func testConfirmationFromASheetDoesNotDismissTheUnderlyingEditor() async throws {
        let session = try await makeSession(inSheet: true)
        XCTAssertEqual(session.coordinator.host?.preferredStyle, .alert)
        XCTAssertNotNil(session.sheet?.presentedViewController)
        session.coordinator.dismissWithoutAction()
        try await waitUntil { session.coordinator.host == nil && session.sheet?.presentedViewController == nil }
        XCTAssertTrue(session.window.rootViewController?.presentedViewController === session.sheet)
        XCTAssertNil(session.sheet?.presentedViewController)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
    }

    func testChangingTheAppearanceUpdatesTheExistingDialogWithoutReopeningIt() async throws {
        let session = try await makeSession()
        let originalHost = try XCTUnwrap(session.coordinator.host)
        session.coordinator.owner = presenter(session.state, colorScheme: .dark)
        session.coordinator.synchronize(from: session.anchor)
        XCTAssertTrue(session.coordinator.host === originalHost)
        XCTAssertEqual(session.coordinator.host?.overrideUserInterfaceStyle, .dark)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
    }

    func testARequestReopenedDuringDismissalWaitsForTheOldController() async throws {
        let session = try await makeSession()
        let originalHost = try XCTUnwrap(session.coordinator.host)
        let originalID = try XCTUnwrap(session.coordinator.presentationID)
        session.state.presented = false
        session.coordinator.synchronize(from: session.anchor)
        session.state.presented = true
        session.coordinator.synchronize(from: session.anchor)
        try await waitUntil {
            guard let host = session.coordinator.host else { return false }
            return host !== originalHost && host.view.window != nil && !host.isBeingPresented
        }
        XCTAssertNotNil(session.coordinator.host)
        XCTAssertFalse(session.coordinator.host === originalHost)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        session.coordinator.confirm(for: originalID)
        session.coordinator.cancel(for: originalID)
        try await spin()
        XCTAssertTrue(session.state.presented)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertEqual(session.state.cancelCount, 0)
        XCTAssertNotNil(session.coordinator.host)
    }

    func testCompletedDialogIgnoresItsOldConfirmationAndCancellationCallbacks() async throws {
        let session = try await makeSession()
        let originalID = try XCTUnwrap(session.coordinator.presentationID)
        session.coordinator.confirm(for: originalID)
        try await waitUntil { !session.state.presented && session.coordinator.host == nil }
        session.coordinator.confirm(for: originalID)
        session.coordinator.cancel(for: originalID)
        session.coordinator.confirm()
        session.coordinator.cancel()
        try await spin()
        XCTAssertEqual(session.state.confirmedPayloads, ["budget-rule"])
        XCTAssertEqual(session.state.cancelCount, 0)
        XCTAssertFalse(session.state.presented)
    }

    func testRemovingThePresenterCancelsAnInFlightConfirmation() async throws {
        let session = try await makeSession()
        session.coordinator.confirm()
        session.coordinator.dismissImmediately()
        try await spin()
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertEqual(session.state.payload, "budget-rule")
        XCTAssertNil(session.coordinator.host)
    }

    func testExplicitCancelCanStartTheNextConfirmationWithoutAStaleTimer() async throws {
        let session = try await makeSession()
        let nextState = State()
        nextState.presented = false
        let next = AppConfirmationPresenter.Coordinator(presenter(nextState))
        let firstState = session.state
        let anchor = session.anchor
        addTeardownBlock {
            next.dismissImmediately()
        }
        session.coordinator.owner = AppConfirmationPresenter(isPresented: Binding(
            get: { firstState.presented },
            set: { firstState.presented = $0 }
        ), colorScheme: .light, title: "转移并删除？", message: "现有账目保持不变。",
        confirmText: "转移并删除", cancelText: "取消", destructive: false,
        onCancel: {
            firstState.cancelCount += 1
            nextState.presented = true
            next.synchronize(from: anchor)
        }, onConfirm: {})
        session.coordinator.cancel()
        session.coordinator.cancel()
        try await waitUntil {
            guard let host = next.host else { return false }
            return session.coordinator.host == nil && host.view.window != nil && !host.isBeingPresented
        }
        XCTAssertEqual(session.state.cancelCount, 1)
        XCTAssertFalse(session.state.presented)
        XCTAssertNil(session.coordinator.host)
        XCTAssertTrue(nextState.presented)
        XCTAssertNotNil(next.host)
        session.coordinator.synchronize(from: session.anchor)
        XCTAssertNotNil(next.host)
        XCTAssertTrue(nextState.confirmedPayloads.isEmpty)
    }

    private func makeSession(inSheet: Bool = false) async throws -> Session {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 912)
        let anchor = AppDialogAnchorController()
        var appeared = false
        anchor.onReady = { appeared = true }
        let sheet: UINavigationController?
        if inSheet {
            sheet = UINavigationController(rootViewController: anchor)
            window.rootViewController = UIViewController()
        } else {
            sheet = nil
            window.rootViewController = anchor
        }
        let state = State()
        let coordinator = AppConfirmationPresenter.Coordinator(presenter(state))
        let session = Session(window: window, previousKeyWindow: previousKeyWindow, anchor: anchor,
                              sheet: sheet, coordinator: coordinator, state: state)
        addTeardownBlock { try await session.close() }
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        if let sheet {
            sheet.modalPresentationStyle = .pageSheet
            window.rootViewController?.present(sheet, animated: false)
        }
        try await waitUntil {
            appeared && anchor.view.window === window && anchor.transitionCoordinator == nil
                && (sheet == nil || (sheet?.presentingViewController != nil
                    && sheet?.isBeingPresented == false && sheet?.transitionCoordinator == nil))
        }
        coordinator.synchronize(from: anchor)
        try await waitUntil {
            guard let host = coordinator.host else { return false }
            return host.view.window === window && !host.isBeingPresented && host.transitionCoordinator == nil
        }
        return session
    }

    private func presenter(_ state: State, colorScheme: ColorScheme = .light) -> AppConfirmationPresenter {
        AppConfirmationPresenter(isPresented: Binding(
            get: { state.presented },
            set: { state.presented = $0; if !$0 { state.payload = nil } }
        ), colorScheme: colorScheme, title: "删除预算规则？", message: "已经记录的账单不会改变。",
        confirmText: "删除", cancelText: "取消", destructive: true,
        onCancel: { state.cancelCount += 1 },
        onConfirm: { if let payload = state.payload { state.confirmedPayloads.append(payload) } })
    }

    private func spin(_ seconds: TimeInterval = 0.6) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // CI animations can outlast a fixed sleep; keep the actual dismissal/presentation assertions strict.
    private func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Native presentation did not reach the expected state", file: file, line: line)
        if !condition() { throw PresentationTimeout() }
    }

    private struct PresentationTimeout: Error {}

    private final class State {
        var presented = true
        var payload: String? = "budget-rule"
        var confirmedPayloads: [String] = []
        var cancelCount = 0
    }

    @MainActor private struct Session {
        let window: UIWindow
        let previousKeyWindow: UIWindow?
        let anchor: AppDialogAnchorController
        let sheet: UINavigationController?
        let coordinator: AppConfirmationPresenter.Coordinator
        let state: State

        func close() async throws {
            let root = window.rootViewController
            let dialog = coordinator.host ?? anchor.presentedViewController
            coordinator.dismissImmediately()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            let deadline = Date().addingTimeInterval(5)
            while anchor.presentedViewController != nil || dialog?.isBeingDismissed == true {
                guard Date() < deadline else {
                    XCTFail("Native dialog cleanup did not finish")
                    throw PresentationTimeout()
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            if let sheet, let root {
                var dismissed = false
                root.dismiss(animated: false) { dismissed = true }
                while !dismissed || root.presentedViewController != nil || sheet.transitionCoordinator != nil {
                    guard Date() < deadline else {
                        XCTFail("Native sheet cleanup did not finish")
                        throw PresentationTimeout()
                    }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }
}
