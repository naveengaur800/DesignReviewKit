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
        configuration: .init(tokenResolver: DemoDesignTokens())
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .designInspector(inspector)
        }
    }
}
