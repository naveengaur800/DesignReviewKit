# DesignReviewKit

Capture, annotate, measure, inspect fonts, and export design feedback — from inside your iOS app.

<p align="center">
  <img src="Assets/home.png" width="156" alt="Demo app before entering review mode" />
  <img src="Assets/annotate.png" width="156" alt="Annotation canvas with severity-colored rectangles" />
  <img src="Assets/comment.png" width="156" alt="Comment sheet with severity picker" />
  <img src="Assets/measure.png" width="156" alt="Measurement mode showing spacing between elements" />
  <img src="Assets/typography.png" width="156" alt="Typography mode revealing the resolved font of a tapped text element" />
  <img src="Assets/export.png" width="156" alt="Generated PDF report preview" />
</p>

## Overview

DesignReviewKit lets designers flag UI issues where they see them. A trigger in the
host app freezes the current screen into a capture; the designer draws rectangles
over problem areas, attaches severity-rated commentary to each, and repeats across
as many screens as the review needs. The session ends in a shareable PDF report —
one page per issue, with the annotated screenshot beside the comment.

The package owns the entire flow after the trigger. The host app contributes three
lines: create an inspector, inject it, and call `beginCapture(in:)` when the
designer asks for it.

## Features

- **Frozen-screenshot annotation** — drag to draw rectangles, move and resize them
  with handles. Every annotation carries a comment by construction: the comment
  sheet appears the moment a rectangle is drawn, and cancelling it removes the
  rectangle.
- **Severity-driven visuals** — Low / Medium / High recolor the annotation live
  and drive the report's legend. Issue numbers are derived from creation order
  across the whole session, so deleting one renumbers the rest automatically.
- **Multi-screen sessions** — close the inspector, navigate the app, trigger it
  again; screens accumulate into one session with a thumbnail strip. Screens left
  without annotations evaporate, and a session whose screens are all empty ends
  itself.
- **Measurement mode** — drag to read distances in true screenshot points, with
  endpoints snapping to real element edges (recorded from the view, layer, and
  accessibility hierarchies at capture time — hairline dividers included) and a
  guide that lights up along the snapped edge. Long-press an element for a glass
  menu and read its spacing to every neighbor at once.
- **Typography mode** — tap any text element to read the font it actually
  rendered with: face name, point size, and color (swatch + hex), one row per
  styled run, custom fonts and Dynamic Type resolution included. Text elements are outlined for
  discovery, overlapping ones cycle by tap, and a copy affordance carries
  `Face · size · #hex — "text"` straight into an annotation comment. Hosts can
  map readings to their own design-token names (`headingM · brandBlue`) by
  supplying a `DesignTokenResolving` in the inspector's configuration. SwiftUI text is
  recovered by reflecting into the render graph at capture time; UIKit labels
  read directly. Readouts are tooling only — they never enter the report.
- **Accessibility mode** — tap any element to read the exact accessibility
  properties a developer set on it: label, value, hint, traits, and
  `accessibilityIdentifier`. Every element is outlined, so the overlay doubles as
  a map of what VoiceOver can reach and in what order; missing labels on
  interactive elements are flagged. Overlapping elements cycle by tap, and a copy
  affordance carries the summary into an annotation comment. Reading SwiftUI's
  tree needs a small host-side runtime enabler
  (§ [Accessibility mode](#accessibility-mode-host-setup)); the package itself
  stays public-API only.
- **PDF reports** — landscape A4: a cover page with app, device, and severity
  metadata, then one page per issue with the full screenshot (siblings ghosted)
  beside the commentary. Annotations render vectorially, crisp at any zoom.
  Preview in-app, share anywhere via the system share sheet.
- **Liquid Glass UI** — the inspector presents as Apple's screenshot-editor
  pattern: the capture freezes in place, springs into a rounded card, and all
  chrome floats in glass. Built natively for iOS 26.

## Getting Started

Create one `DesignInspector` at the composition root and inject it — there is no
shared instance; the host owns the lifecycle:

```swift
@main
struct MyApp: App {
    @State private var inspector = DesignInspector()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .designInspector(inspector)
        }
    }
}
```

Wire any trigger — shake, debug menu, toolbar button — to begin a capture:

```swift
@Environment(\.designInspector) private var inspector

inspector?.beginCapture(in: windowScene)
```

Gate the trigger to Debug and TestFlight builds; the package ships inert when
`Configuration(isEnabled: false)` is passed.

## Accessibility mode (host setup)

> **Status:** shipping as the `InspectorTool.accessibility` mode inside the
> package — the tap-to-inspect flow, outlines, flags, and card are live and
> verified on the iOS 26 simulator. On-device verification of the runtime enabler
> is the one remaining check. See `AccessibilityInspector-SPEC.md`.

Accessibility mode reads the same properties VoiceOver reads and shows them on a
card when you tap an element. Because iOS does not materialize a process's
accessibility tree — especially SwiftUI's bridged nodes — while no assistive
technology is attached, the mode needs that tree switched on at capture time.
**The package never links a private symbol to do this.** Instead the host
provides a tiny enabler and the package calls it once at creation. Adopting it is
three additions on the client side.

### 1. Add the enabler to the app target

The private symbol is wrapped so it compiles **only** into your internal build
configurations — distributed builds contain no private API and the call is a
no-op there.

```swift
//
//  AXRuntimeEnabler.swift
//  MyApp   (app target — never the package)
//

import Foundation

/// Host-side accessibility-runtime enabler for DesignReviewKit's accessibility
/// inspector. The private symbol compiles only under `DESIGN_REVIEW_TOOLS`, so
/// App Store / distributed builds carry no private API and this is a no-op there.
enum AXRuntimeEnabler {

    @discardableResult
    static func enableAutomation() -> Bool {
        #if DESIGN_REVIEW_TOOLS
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LOCAL),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else {
            return false
        }
        typealias SetAutomationEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetAutomationEnabled.self)(1)
        return true
        #else
        return false
        #endif
    }
}
```

### 2. Hand the enabler to the inspector

The only new package API is one closure on `Configuration`. The package invokes
it immediately before capture (lazy enabling is sufficient — no launch-time
requirement), so it owns the timing while the host owns the private call.

```swift
@State private var inspector = DesignInspector(
    configuration: .init(
        accessibilityRuntimeEnabler: { AXRuntimeEnabler.enableAutomation() }
    )
)
```

### 3. Set the build flag

On the app target, for your internal configuration(s) **only**, add
`DESIGN_REVIEW_TOOLS` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. Do **not** gate on
`DEBUG`: SwiftPM builds packages in release mode under custom-named
configurations, so a `DEBUG` gate silently compiles out in exactly the internal
builds that need it.

### What the reviewer does

Nothing extra. No turning on VoiceOver, no Settings toggle — the enabler switches
the runtime on for the instant of capture. The reviewer triggers the inspector as
usual, selects the accessibility tool, and taps elements. When the enabler is
absent (distributed build, or a future OS breaks it), the mode shows one
explanatory banner instead of an empty screen.

## Repository Layout

| Path | Contents |
|---|---|
| `DesignReviewKit/` | The Swift package — add this folder as a local package dependency |
| `View Drawing/` | Demo app showing integration: shake trigger + toolbar button |
| `View Drawing/Spike/` | Host-side accessibility enabler (`AXRuntimeEnabler`, the reference for §[Accessibility mode](#accessibility-mode-host-setup)) plus the on-device enablement test harness |
| `DesignReviewKit-SPEC.md` | The original product specification |
| `FontInspector-SPEC.md` | Typography mode: decisions and behavior |
| `FontInspector-ARCHITECTURE.md` | Typography mode: extraction mechanism + repair playbook for future iOS releases |
| `AccessibilityInspector-SPEC.md` | Accessibility inspector: decisions, the enablement spike results, and client integration |

The package also ships a DocC catalog — build documentation in Xcode
(<kbd>⌃⇧⌘D</kbd>) for the full guide.

## Requirements

- iOS 26.0+
- Swift 6.2 / Xcode 26
- SwiftUI host or UIKit host (the core API is window-scene based; the SwiftUI
  modifier is a thin wrapper)

## Demo

Open `View Drawing.xcodeproj`, run on any iPhone simulator, and tap the dashed
rectangle in the toolbar (or press <kbd>⌃⌘Z</kbd> to shake). Draw a rectangle on
the profile card, give it a severity and a comment, then export the PDF from the
document button in the chrome.
