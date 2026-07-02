//
//  View_DrawingApp.swift
//  View Drawing
//
//  Created by Naveen Gaur on 10/6/2026.
//

import DesignReviewKit
import SwiftUI

@main
struct View_DrawingApp: App {

    /// Composition root owns the inspector; views reach it via the environment.
    /// The token resolver maps typography readings to the demo's design-token names.
    @State
    private var inspector = DesignInspector(
        configuration: .init(
            tokenResolver: DemoDesignTokens(),
            // Host-side hook: materialize the accessibility tree so the package's
            // accessibility mode can read SwiftUI elements. Package stays
            // public-API only; this private call lives in the app target.
            accessibilityRuntimeEnabler: { _ = AXRuntimeEnabler.enableAutomation() }
        )
    )

    /// Show the accessibility-runtime spike instead of the demo. Driven by the
    /// `-SpikeMode 1` launch argument; the normal app is untouched without it.
    private let showsSpike: Bool

    init() {
        let defaults = UserDefaults.standard
        showsSpike = defaults.bool(forKey: "SpikeMode")

        // Force a known runtime state before any view builds (SPEC §7). The
        // daemon flag persists across launches, so each measurement pins it
        // explicitly rather than inheriting the previous run's state.
        if defaults.bool(forKey: "SpikeEnableAXAtLaunch") {
            AXRuntimeEnabler.setAutomation(true)
        } else if defaults.bool(forKey: "SpikeForceOff") {
            AXRuntimeEnabler.setAutomation(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            if showsSpike {
                AccessibilitySpikeView()
            } else {
                ContentView()
                    .designInspector(inspector)
            }
        }
    }
}
