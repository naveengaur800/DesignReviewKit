# ``DesignReviewKit``

Capture, annotate, and export design feedback from inside any iOS app.

## Overview

DesignReviewKit lets designers flag UI issues where they see them. A trigger in the
host app freezes the current screen into a capture; the designer draws rectangles
over problem areas, attaches severity-rated commentary to each, and repeats across
as many screens as the review needs. The session ends in a shareable PDF report —
one page per issue, with the annotated screenshot beside the comment.

The package owns the entire flow after the trigger. The host app contributes three
lines: create an inspector, inject it, and call ``DesignInspector/beginCapture(in:)``
when the designer asks for it.

## Getting Started

Create one ``DesignInspector`` at the composition root and inject it into the view
tree. There is no shared instance — the host owns the lifecycle.

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

Gate the trigger to Debug and TestFlight builds; the package itself ships inert
when ``DesignInspector/Configuration/isEnabled`` is `false`.

## How a Session Works

- ``DesignInspector/beginCapture(in:)`` screenshots the host's key window *before*
  presenting anything, so the inspector never appears in its own captures.
- The first capture starts a session; later captures append screens to it. The
  session lives in memory until explicitly ended.
- Every annotation carries a comment by construction: the comment sheet appears
  the moment a rectangle is drawn, and cancelling it removes the rectangle.
- Screens closed without annotations are dropped. A session whose screens are all
  empty ends itself, so accidental triggers leave no trace.
- Issue numbers are derived from creation order across the whole session —
  deleting an annotation renumbers the rest automatically.
- Measurement mode (the ruler control) reads drag distances in screenshot
  points. Endpoints snap to element edges recorded at capture time, and a
  guide lights up along the snapped edge so landing on it is unmistakable.
  Long-press an element for its glass menu and choose Spacing to flash the
  distances from its edges to the nearest neighboring elements or its
  container. Measurements are tooling only — they never enter the report.
- Typography mode (the Aa control) outlines every captured text element; tap
  one to read the resolved font — face name and point size, one row per styled
  run — with a copy affordance for carrying the identity into an annotation
  comment. Like measurements, font readouts never enter the report.
- Export renders a landscape-A4 PDF: a cover page with app and device metadata,
  then one page per issue. Exporting does not end the session.

## Topics

### Essentials

- ``DesignInspector``
- ``DesignInspector/beginCapture(in:)``
- ``DesignInspector/Configuration``

### SwiftUI Integration

- ``SwiftUICore/View/designInspector(_:)``
- ``SwiftUICore/EnvironmentValues/designInspector``
