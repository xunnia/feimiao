import SwiftUI
import UIKit

extension View {
    func appConfirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String,
        confirmText: String = "确定",
        cancelText: String = "取消",
        destructive: Bool = false,
        onCancel: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(AppConfirmationDialogModifier(isPresented: isPresented, title: title, message: message,
                                              confirmText: confirmText, cancelText: cancelText,
                                              destructive: destructive, onCancel: onCancel, onConfirm: onConfirm))
    }
}

private struct AppConfirmationDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    @AppThemeContext private var theme
    let title: String
    let message: String
    let confirmText: String
    let cancelText: String
    let destructive: Bool
    let onCancel: (() -> Void)?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.background {
            AppConfirmationPresenter(isPresented: $isPresented, colorScheme: theme.isDark ? .dark : .light,
                                     title: title, message: message, confirmText: confirmText,
                                     cancelText: cancelText, destructive: destructive,
                                     onCancel: onCancel, onConfirm: onConfirm)
        }
    }
}

/// Keep native layout, materials, Dynamic Type and modal accessibility; do not draw over Apple's alert.
@MainActor
enum AppNativeConfirmation {
    static func makeController(
        title: String, message: String, confirmText: String, cancelText: String,
        destructive: Bool, colorScheme: ColorScheme,
        onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void
    ) -> UIAlertController {
        let controller = UIAlertController(title: title, message: message.isEmpty ? nil : message,
                                           preferredStyle: .alert)
        // Let UIKit start its automatic dismissal before the coordinator observes its transition.
        let cancel = UIAlertAction(title: cancelText, style: .cancel) { _ in
            DispatchQueue.main.async(execute: onCancel)
        }
        // UIKit's destructive style forces system red. Use public alert tint and make cancel the safe default.
        let confirm = UIAlertAction(title: confirmText, style: .default) { _ in
            DispatchQueue.main.async(execute: onConfirm)
        }
        controller.addAction(cancel)
        controller.addAction(confirm)
        controller.view.accessibilityIdentifier = "app-confirmation-dialog"
        update(controller, title: title, message: message, destructive: destructive, colorScheme: colorScheme)
        return controller
    }

    static func update(_ controller: UIAlertController, title: String, message: String,
                       destructive: Bool, colorScheme: ColorScheme) {
        controller.title = title
        controller.message = message.isEmpty ? nil : message
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        controller.view.tintColor = UIColor(destructive ? Color.warning : Color.statisticsAccent)
        controller.preferredAction = destructive ? controller.actions.first : controller.actions.last
    }
}

/// UIKit dismissal completion lets a multi-step flow open its next native dialog without a timer.
struct AppConfirmationPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let colorScheme: ColorScheme
    let title: String
    let message: String
    let confirmText: String
    let cancelText: String
    let destructive: Bool
    let onCancel: (() -> Void)?
    let onConfirm: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> AppDialogAnchorController {
        let controller = AppDialogAnchorController()
        controller.onReady = { [weak controller, weak coordinator = context.coordinator] in
            guard let controller else { return }
            coordinator?.synchronize(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ controller: AppDialogAnchorController, context: Context) {
        context.coordinator.owner = self
        context.coordinator.synchronize(from: controller)
    }

    static func dismantleUIViewController(_ controller: AppDialogAnchorController, coordinator: Coordinator) {
        coordinator.dismissImmediately()
    }

    @MainActor final class Coordinator {
        var owner: AppConfirmationPresenter
        private(set) var host: UIAlertController?
        private(set) var presentationID: UUID?
        private weak var anchor: AppDialogAnchorController?
        private var completing = false

        init(_ owner: AppConfirmationPresenter) { self.owner = owner }

        func synchronize(from anchor: AppDialogAnchorController) {
            self.anchor = anchor
            guard !completing else { return }
            guard owner.isPresented else {
                if let presentationID { close(for: presentationID, clearBinding: false, action: nil) }
                return
            }
            if let host {
                AppNativeConfirmation.update(host, title: owner.title, message: owner.message,
                                             destructive: owner.destructive, colorScheme: owner.colorScheme)
                return
            }
            guard anchor.view.window != nil, !anchor.isBeingDismissed,
                  anchor.presentedViewController == nil else { return }
            let identifier = UUID()
            presentationID = identifier
            let controller = AppNativeConfirmation.makeController(
                title: owner.title, message: owner.message, confirmText: owner.confirmText,
                cancelText: owner.cancelText, destructive: owner.destructive, colorScheme: owner.colorScheme,
                onCancel: { [weak self] in self?.cancel(for: identifier) },
                onConfirm: { [weak self] in self?.confirm(for: identifier) })
            host = controller
            anchor.view.window?.endEditing(true)
            anchor.present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        func dismissWithoutAction() {
            guard let presentationID else { return }
            close(for: presentationID, clearBinding: true, action: nil)
        }

        func cancel() {
            guard let presentationID else { return }
            cancel(for: presentationID)
        }

        func confirm() {
            guard let presentationID else { return }
            confirm(for: presentationID)
        }

        func cancel(for identifier: UUID) {
            guard owner.isPresented else { return }
            close(for: identifier, clearBinding: true, action: owner.onCancel)
        }

        func confirm(for identifier: UUID) {
            guard owner.isPresented else { return }
            close(for: identifier, clearBinding: true, action: owner.onConfirm)
        }

        func dismissImmediately() {
            presentationID = nil
            completing = false
            let controller = host
            host = nil
            controller?.dismiss(animated: false)
        }

        private func close(for identifier: UUID, clearBinding: Bool, action: (() -> Void)?) {
            guard !completing, presentationID == identifier, let host else { return }
            completing = true
            host.actions.forEach { $0.isEnabled = false }
            let finish = { [weak self] in
                guard let self, self.presentationID == identifier else { return }
                self.host = nil
                self.presentationID = nil
                // Consume payload before the binding setter clears it; ignore callbacks from the closed alert.
                action?()
                if clearBinding { self.owner.isPresented = false }
                self.completing = false
                if let anchor = self.anchor { self.synchronize(from: anchor) }
            }
            if host.isBeingDismissed, let transition = host.transitionCoordinator {
                if !transition.animate(alongsideTransition: nil, completion: { _ in finish() }) {
                    DispatchQueue.main.async(execute: finish)
                }
            } else if host.presentingViewController != nil {
                host.dismiss(animated: !UIAccessibility.isReduceMotionEnabled, completion: finish)
            } else {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }
}

final class AppDialogAnchorController: UIViewController {
    var onReady: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onReady?()
    }
}
