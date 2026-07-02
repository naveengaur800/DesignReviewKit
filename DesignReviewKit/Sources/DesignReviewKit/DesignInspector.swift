//
//  DesignInspector.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI
import UIKit

/// Entry point for design review: capture screens, annotate them, and export a PDF report.
///
/// Create one instance at the host app's composition root and inject it wherever the
/// trigger lives (shake handler, debug menu, toolbar button). All session state lives
/// in this instance — there is no shared global.
///
/// ```swift
/// let inspector = DesignInspector()
/// // on shake:
/// inspector.beginCapture(in: windowScene)
/// ```
@MainActor
public final class DesignInspector {

    /// Host-supplied behavior switches.
    public struct Configuration: Sendable {
        /// Master switch — hosts that gate the tool at runtime (feature flag) set this once.
        public var isEnabled: Bool

        /// Map typography-mode readings to the host's design-token names;
        /// `nil` shows raw readings (face, size, hex) everywhere.
        public var tokenResolver: (any DesignTokenResolving)?

        public init(isEnabled: Bool = true, tokenResolver: (any DesignTokenResolving)? = nil) {
            self.isEnabled = isEnabled
            self.tokenResolver = tokenResolver
        }
    }

    private let configuration: Configuration
    private let capturer = ScreenCapturer()
    private var viewModel: InspectorViewModel?
    private var overlayWindow: UIWindow?

    /// Whether a session with at least one captured screen is open.
    public var hasActiveSession: Bool {
        viewModel != nil
    }

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Capture the scene's key window and present the annotation UI.
    ///
    /// Starts a new session, or resumes the open one by appending a fresh capture.
    /// No-op while the inspector is already presented.
    public func beginCapture(in windowScene: UIWindowScene) {
        guard configuration.isEnabled, overlayWindow == nil else { return }
        guard let hostWindow = hostWindow(in: windowScene),
              let screen = capturer.capture(window: hostWindow) else { return }

        if let viewModel {
            viewModel.appendCapturedScreen(screen)
        } else {
            let session = ReviewSession(
                startedAt: Date(),
                appMetadata: .current(),
                deviceMetadata: .current(for: hostWindow),
                screens: [screen]
            )
            viewModel = InspectorViewModel(
                session: session,
                tokenResolver: configuration.tokenResolver,
                onSuspend: { [weak self] in self?.dismissOverlay() },
                onEndSession: { [weak self] in self?.endSession() }
            )
        }

        presentOverlay(in: windowScene)
    }

    private func hostWindow(in windowScene: UIWindowScene) -> UIWindow? {
        windowScene.keyWindow ?? windowScene.windows.first
    }

    private func presentOverlay(in windowScene: UIWindowScene) {
        guard let viewModel else { return }
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1

        // Keep the window transparent: the entry transition starts with the capture
        // pixel-aligned over the live UI, and an opaque hosting view would flash.
        let hostingController = UIHostingController(rootView: InspectorRootView(viewModel: viewModel))
        hostingController.view.backgroundColor = .clear
        window.backgroundColor = .clear
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        overlayWindow = window
    }

    /// Hide the inspector while keeping the session alive for the next capture.
    private func dismissOverlay() {
        let windowScene = overlayWindow?.windowScene
        overlayWindow?.isHidden = true
        overlayWindow = nil

        // UIKit doesn't reliably promote another window to key when the key window is
        // removed; re-key the host window so its responder chain (shake) keeps working.
        windowScene?.windows
            .first { !$0.isHidden && $0.windowLevel == .normal }?
            .makeKey()
    }

    /// Tear down the session entirely (End Session, or last screen discarded).
    private func endSession() {
        dismissOverlay()
        viewModel = nil
    }
}
