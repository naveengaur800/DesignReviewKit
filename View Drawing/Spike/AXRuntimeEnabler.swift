//
//  AXRuntimeEnabler.swift
//  View Drawing
//
//  Created by Naveen Gaur on 03/07/2026.
//

import Foundation

/// Reference implementation of the host-side accessibility-runtime enabler
/// (AccessibilityInspector-SPEC §3.1).
///
/// Lives in the **app target**, never in DesignReviewKit — the package stays
/// public-API only. It is handed to the inspector as
/// `Configuration.accessibilityRuntimeEnabler`, so it must be callable from a
/// `@Sendable` closure: `nonisolated`, touching no main-actor state.
///
/// Every private reference — the `dlopen`, `dlsym`, and the `_AXS…` symbol
/// names — is gated behind `DESIGN_REVIEW_TOOLS`, so a distributed build (where
/// the flag is absent) compiles this to a no-op with no private symbol or symbol
/// string in the binary. Define the flag in internal configurations only, via
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
///
/// Materializing the in-process accessibility tree is the one thing public API
/// cannot do with no assistive technology attached. This flips the same switch
/// KIF, EarlGrey, and AccessibilitySnapshot have used since ~2013.
nonisolated enum AXRuntimeEnabler {

    /// Whether the accessibility automation runtime is currently enabled.
    static var isAutomationEnabled: Bool {
        #if DESIGN_REVIEW_TOOLS
        return withSymbol("_AXSAutomationEnabled", as: (@convention(c) () -> Int32).self) { $0() != 0 } ?? false
        #else
        return false
        #endif
    }

    /// Enable the automation runtime so the process materializes its
    /// accessibility tree (including SwiftUI's bridged nodes).
    ///
    /// - Returns: Whether the private symbol resolved and was invoked. `false`
    ///   in distributed builds (flag absent) or if a future OS removed the
    ///   symbol — the caller degrades gracefully, never crashes.
    @discardableResult
    static func enableAutomation() -> Bool {
        setAutomation(true)
    }

    /// Set the automation runtime flag. The setting persists at the
    /// accessibility daemon across launches, so the test harness forces a known
    /// state per launch rather than trusting the inherited one.
    @discardableResult
    static func setAutomation(_ enabled: Bool) -> Bool {
        #if DESIGN_REVIEW_TOOLS
        return withSymbol("_AXSSetAutomationEnabled", as: (@convention(c) (Int32) -> Void).self) { setEnabled in
            setEnabled(enabled ? 1 : 0)
            return true
        } ?? false
        #else
        return false
        #endif
    }

    #if DESIGN_REVIEW_TOOLS
    private static let libraryPath = "/usr/lib/libAccessibility.dylib"

    /// Resolve a symbol from libAccessibility and hand it to `body`, or return
    /// `nil` when the library or symbol is unavailable.
    private static func withSymbol<Function, Result>(
        _ name: String,
        as type: Function.Type,
        _ body: (Function) -> Result
    ) -> Result? {
        guard let handle = dlopen(libraryPath, RTLD_LOCAL) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, name) else { return nil }
        return body(unsafeBitCast(symbol, to: Function.self))
    }
    #endif
}
