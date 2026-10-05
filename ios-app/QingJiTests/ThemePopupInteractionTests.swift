import XCTest
import SwiftUI
import UIKit
@testable import QingJi

@MainActor
final class ThemePopupInteractionTests: XCTestCase {
    func testRepeatedConfirmationConsumesPayloadOnceBeforeClearingIt() throws {
        let session = try makeSession()
        defer { session.close() }
        XCTAssertNotNil(session.coordinator.host)
        session.coordinator.confirm()
        session.coordinator.confirm()
        waitUntil { !session.state.presented && session.coordinator.host == nil }
        XCTAssertEqual(session.state.confirmedPayloads, ["budget-rule"])
        XCTAssertNil(session.state.payload)
        XCTAssertFalse(session.state.presented)
        XCTAssertNil(session.coordinator.host)
    }

    func testProgrammaticDismissalDoesNotExecuteTheExplicitCancelAction() throws {
        let session = try makeSession()
        defer { session.close() }
        session.coordinator.dismissWithoutAction()
        waitUntil { !session.state.presented && session.coordinator.host == nil }
        XCTAssertEqual(session.state.cancelCount, 0)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertFalse(session.state.presented)
    }

    func testCancelExecutesOnlyTheCancelAction() throws {
        let session = try makeSession()
        defer { session.close() }
        session.coordinator.cancel()
        session.coordinator.cancel()
        waitUntil { !session.state.presented && session.coordinator.host == nil }
        XCTAssertEqual(session.state.cancelCount, 1)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertFalse(session.state.presented)
    }

    func testConfirmationFromASheetDoesNotDismissTheUnderlyingEditor() throws {
        let session = try makeSession(inSheet: true)
        defer { session.close() }
        XCTAssertEqual(session.coordinator.host?.preferredStyle, .alert)
        XCTAssertNotNil(session.sheet?.presentedViewController)
        session.coordinator.dismissWithoutAction()
        waitUntil { session.coordinator.host == nil && session.sheet?.presentedViewController == nil }
        XCTAssertTrue(session.window.rootViewController?.presentedViewController === session.sheet)
        XCTAssertNil(session.sheet?.presentedViewController)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
    }

    func testChangingTheAppearanceUpdatesTheExistingDialogWithoutReopeningIt() throws {
        let session = try makeSession()
        defer { session.close() }
        let originalHost = try XCTUnwrap(session.coordinator.host)
        session.coordinator.owner = presenter(session.state, colorScheme: .dark)
        session.coordinator.synchronize(from: session.anchor)
        XCTAssertTrue(session.coordinator.host === originalHost)
        XCTAssertEqual(session.coordinator.host?.overrideUserInterfaceStyle, .dark)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
    }

    func testARequestReopenedDuringDismissalWaitsForTheOldController() throws {
        let session = try makeSession()
        defer { session.close() }
        let originalHost = try XCTUnwrap(session.coordinator.host)
        let originalID = try XCTUnwrap(session.coordinator.presentationID)
        session.state.presented = false
        session.coordinator.synchronize(from: session.anchor)
        session.state.presented = true
        session.coordinator.synchronize(from: session.anchor)
        waitUntil {
            guard let host = session.coordinator.host else { return false }
            return host !== originalHost && host.view.window != nil && !host.isBeingPresented
        }
        XCTAssertNotNil(session.coordinator.host)
        XCTAssertFalse(session.coordinator.host === originalHost)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        session.coordinator.confirm(for: originalID)
        session.coordinator.cancel(for: originalID)
        spin()
        XCTAssertTrue(session.state.presented)
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertEqual(session.state.cancelCount, 0)
        XCTAssertNotNil(session.coordinator.host)
    }

    func testCompletedDialogIgnoresItsOldConfirmationAndCancellationCallbacks() throws {
        let session = try makeSession()
        defer { session.close() }
        let originalID = try XCTUnwrap(session.coordinator.presentationID)
        session.coordinator.confirm(for: originalID)
        waitUntil { !session.state.presented && session.coordinator.host == nil }
        session.coordinator.confirm(for: originalID)
        session.coordinator.cancel(for: originalID)
        session.coordinator.confirm()
        session.coordinator.cancel()
        spin()
        XCTAssertEqual(session.state.confirmedPayloads, ["budget-rule"])
        XCTAssertEqual(session.state.cancelCount, 0)
        XCTAssertFalse(session.state.presented)
    }

    func testRemovingThePresenterCancelsAnInFlightConfirmation() throws {
        let session = try makeSession()
        defer { session.close() }
        session.coordinator.confirm()
        session.coordinator.dismissImmediately()
        spin()
        XCTAssertTrue(session.state.confirmedPayloads.isEmpty)
        XCTAssertEqual(session.state.payload, "budget-rule")
        XCTAssertNil(session.coordinator.host)
    }

    func testExplicitCancelCanStartTheNextConfirmationWithoutAStaleTimer() throws {
        let session = try makeSession()
        let nextState = State()
        nextState.presented = false
        let next = AppConfirmationPresenter.Coordinator(presenter(nextState))
        let firstState = session.state
        let anchor = session.anchor
        defer {
            next.dismissImmediately()
            session.close()
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
        waitUntil {
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

    private func makeSession(inSheet: Bool = false) throws -> Session {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 912)
        let anchor = AppDialogAnchorController()
        let sheet: UINavigationController?
        if inSheet {
            sheet = UINavigationController(rootViewController: anchor)
            window.rootViewController = UIViewController()
        } else {
            sheet = nil
            window.rootViewController = anchor
        }
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        if let sheet {
            sheet.modalPresentationStyle = .pageSheet
            window.rootViewController?.present(sheet, animated: false)
        }
        waitUntil {
            anchor.view.window != nil && (sheet == nil || (sheet?.presentingViewController != nil
                && sheet?.isBeingPresented == false))
        }
        let state = State()
        let coordinator = AppConfirmationPresenter.Coordinator(presenter(state))
        coordinator.synchronize(from: anchor)
        waitUntil {
            guard let host = coordinator.host else { return false }
            return host.view.window != nil && !host.isBeingPresented
        }
        return Session(window: window, previousKeyWindow: previousKeyWindow, anchor: anchor, sheet: sheet,
                       coordinator: coordinator, state: state)
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

    private func spin(_ seconds: TimeInterval = 0.6) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // CI animations can outlast a fixed sleep; keep the actual dismissal/presentation assertions strict.
    private func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
        XCTAssertTrue(condition(), "Native presentation did not reach the expected state", file: file, line: line)
    }

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

        func close() {
            coordinator.dismissImmediately()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
    }
}
