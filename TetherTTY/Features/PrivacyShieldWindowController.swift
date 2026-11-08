import SwiftUI
import UIKit

/// Captures the `UIWindowScene` that hosts this view's own window, once it is attached, without
/// relying on `UIApplication.shared.connectedScenes.first` (which would not distinguish between
/// multiple iPad scenes). Purely a thin UIKit bridge; no decision logic lives here.
struct WindowSceneReader: UIViewRepresentable {
    let onChange: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = SceneCaptureView()
        view.onWindowSceneChange = onChange
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class SceneCaptureView: UIView {
        var onWindowSceneChange: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene {
                onWindowSceneChange?(scene)
            }
        }
    }
}

/// Renders either the plain privacy cover (background + sigil, nothing else) or, while a relock
/// is required, the full `LockedVaultView` lock UI — bound directly to the view model so the
/// shield window always reflects its current state.
private struct PrivacyShieldContentView: View {
    @ObservedObject var viewModel: AppLockViewModel

    var body: some View {
        ZStack {
            AbyssBackground()

            if viewModel.isRelockRequired {
                LockedVaultView(
                    isAuthenticating: viewModel.isAuthenticating,
                    errorMessage: viewModel.errorMessage
                ) {
                    Task { await viewModel.unlock() }
                }
            } else {
                SigilMark()
                    .frame(width: 96, height: 96)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Owns a `UIWindow` layered above all of this scene's app windows (including full-screen
/// covers, sheets, and alerts), so the privacy cover / re-lock shield can never be hidden behind
/// app content. All show/hide decisions are made by `AppLockViewModel`; this controller only
/// reflects `isShieldVisible` (and, while visible, resigns any active first responder so no
/// keyboard floats above the shield).
@MainActor
final class PrivacyShieldWindowController {
    private weak var attachedScene: UIWindowScene?
    private weak var viewModel: AppLockViewModel?
    private var window: UIWindow?
    private var hostingController: UIHostingController<PrivacyShieldContentView>?
    private var isVisible = false
    private var sceneObservers: [NSObjectProtocol] = []

    func attach(to windowScene: UIWindowScene, viewModel: AppLockViewModel) {
        guard attachedScene !== windowScene else { return }
        attachedScene = windowScene
        self.viewModel = viewModel

        let hostingController = UIHostingController(rootView: PrivacyShieldContentView(viewModel: viewModel))
        hostingController.view.backgroundColor = .black
        hostingController.view.accessibilityViewIsModal = false

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.isOpaque = true
        window.backgroundColor = .black
        window.isUserInteractionEnabled = true
        window.rootViewController = hostingController
        window.isHidden = true

        self.window = window
        self.hostingController = hostingController

        observeSceneLifecycle(of: windowScene)
    }

    /// Belt-and-braces: SwiftUI's own `scenePhase` environment value is the primary driver (see
    /// `AppShellView`), but it is observed and re-published by SwiftUI itself, which is one more
    /// layer than the raw UIKit scene notifications. Observing the scene directly means the
    /// shield still goes up synchronously even if that SwiftUI hop were ever delayed.
    private func observeSceneLifecycle(of windowScene: UIWindowScene) {
        removeSceneObservers()

        let center = NotificationCenter.default
        sceneObservers = [
            center.addObserver(
                forName: UIScene.willDeactivateNotification,
                object: windowScene,
                queue: .main
            ) { [weak self] _ in
                self?.handleSceneNotification(phase: .inactive)
            },
            center.addObserver(
                forName: UIScene.didEnterBackgroundNotification,
                object: windowScene,
                queue: .main
            ) { [weak self] _ in
                self?.handleSceneNotification(phase: .background)
            }
        ]
    }

    private func handleSceneNotification(phase: ScenePhase) {
        guard let viewModel else { return }
        viewModel.scenePhaseDidChange(to: phase)
        update(isVisible: viewModel.isShieldVisible)
    }

    private func removeSceneObservers() {
        let center = NotificationCenter.default
        sceneObservers.forEach { center.removeObserver($0) }
        sceneObservers.removeAll()
    }

    deinit {
        let center = NotificationCenter.default
        sceneObservers.forEach { center.removeObserver($0) }
    }

    /// Updates visibility to match `AppLockViewModel.isShieldVisible`. Showing is synchronous
    /// (no animation) and cancels any in-flight hide fade, so the shield is guaranteed to be up
    /// before any snapshot can be taken even if a quick inactive→active→inactive sequence races
    /// the fade. Hiding uses a short fade, and its completion only actually hides the window if
    /// nothing re-showed it in the meantime.
    func update(isVisible: Bool) {
        guard let window, let hostingController else { return }
        guard self.isVisible != isVisible else { return }
        self.isVisible = isVisible

        if isVisible {
            // End editing only in this scene's own app windows (not app-wide), so no keyboard
            // stays engaged above content that the shield is about to cover.
            attachedScene?.windows
                .filter { $0 !== window }
                .forEach { $0.endEditing(true) }
            hostingController.view.accessibilityViewIsModal = true
            window.layer.removeAllAnimations()
            window.alpha = 1
            window.isHidden = false
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                window.alpha = 0
            }, completion: { [weak self] _ in
                guard let self, self.isVisible == false else { return }
                // Release VoiceOver confinement only once the shield is actually gone.
                hostingController.view.accessibilityViewIsModal = false
                window.isHidden = true
                window.alpha = 1
            })
        }
    }
}
