# DesignReviewKit — Font Inspector Specification

Reveal the resolved font of any on-screen text from inside the inspector. Companion to `DesignReviewKit-SPEC.md`; supersedes nothing in it.

Feasibility was proven by a working spike on iOS 26.0 (2026-07-02): SwiftUI's render graph is reachable via `Mirror` reflection and yields exact frames, strings, and resolved `UIFont`s — custom families included (verified with `Avenir-Heavy 19pt` as a GT America proxy; all 12 texts on the demo's NavigationStack screens extracted correctly).

## 1. Summary of Decisions

| Decision | Choice |
|---|---|
| SwiftUI font source | Reflection into the private display list (proven by spike), compiled in all configurations — decision revised post-implementation, see §2.4 |
| UIKit font source (v1) | `UILabel` only — covers nav bar titles and `UIButton` internal labels |
| Interaction | "Aa" type mode in the chrome bar: outline all text elements, tap for a detail card |
| Mode model | Tools are mutually exclusive — `activeTool: InspectorTool?` replaces the measurement boolean |
| Readout depth | Core identity: face name, family, point size (per run for mixed-font text) |
| Persistence | Ephemeral, like measurements — never enters the session, annotations, or PDF |
| Handoff | Card offers a copy affordance producing a one-line summary |
| Failure UX | Element still outlines; card shows the string with "Font unavailable" |
| Wholesale breakage | Capture-time canary flags the screen; type mode shows one explanatory banner |
| Font naming | Raw face name is primary (custom fonts are the primary audience); light prettification of `.SFUI-*` faces is a nicety, not a requirement |

## 2. Capture Pipeline

All font data is harvested at capture time in `ScreenCapturer` — the inspector operates on a frozen screenshot, so nothing can be queried later.

### 2.1 Unified element model

Replace `CapturedScreen.elementFrames: [CGRect]` with typed elements:

```swift
nonisolated struct CapturedElement: Sendable, Codable {
    enum Kind: Sendable, Codable {
        case container
        case text(TextAttributes)
    }
    let normalizedRect: CGRect   // unit coordinates, same convention as today
    let kind: Kind
}

nonisolated struct TextAttributes: Sendable, Codable {
    let string: String
    let fonts: [FontIdentity]    // one per distinct run; empty = extraction failed
}

nonisolated struct FontIdentity: Sendable, Codable {
    let faceName: String         // PostScript name, e.g. "GTAmerica-Bold"
    let familyName: String
    let pointSize: CGFloat
}
```

- Measurement/spacing consume `normalizedRect` from the same array — one walk, one dedup pass, text elements remain snap and spacing targets. `ElementSpacingCalculator` and `MeasurementCanvasView` signatures change from `[CGRect]` to `[CapturedElement]` (or map to rects at the call site).
- `fonts` is an array because the payload is an `NSAttributedString`; mixed-run text (inline bold, styled spans) reports each distinct font.

### 2.2 Walk sources

The existing three sources (subviews, accessibility, layers) continue to produce `.container` elements. Two text sources join them:

1. **SwiftUI display list**. Per hosting view — match class names containing `"Hosting"`, not just `_UIHostingView`; NavigationStack content lives under `NavigationStackHostingController`'s inner view — locate the render graph's `SwiftUI.DisplayList` via bounded breadth-first `Mirror` search, then recursively parse items in paint order:
   - `.effect` case → recurse into the nested list.
   - `.content` case with `.text(StyledTextContentView, CGSize)` → breadth-first search the payload for its `NSAttributedString` (public API from there): string and per-run fonts.
   - Unknown cases → search for nested display lists and recurse.
   - **Geometry comes from the layer tree, not the display list.** Item frames inside scroll containers are in content coordinates (the live offset exists only in the platform layers — found during simulator validation: outlines floated one nav-bar height off). Each text payload is matched to its `CGDrawingLayer` in paint order by exact size (±0.5pt), preferring the candidate nearest the payload's approximate display-list position, and the layer's window frame is authoritative. Unmatched payloads drop — failure is omission, never misplacement. See `FontInspector-ARCHITECTURE.md` §3.
2. **UILabel**. The subview walk already visits labels for bounds; additionally read `font` / `attributedText` into `TextAttributes`. Catches UIKit hosts, `UIKitNavigationBar` titles, and button labels.

Dedup policy between sources: when a text element and a container coincide (same rect within tolerance), keep the text element.

The accessibility walk contributes nothing for SwiftUI text (verified: hosting views expose no elements synchronously) — do not rely on it for strings.

### 2.3 Canary

If the layer walk detected `CGDrawingLayer`s (SwiftUI drew text) but the display-list extraction produced zero text elements, set `CapturedScreen.fontExtractionUnavailable = true`. This distinguishes "extractor broken by an OS update" from "no SwiftUI text on screen". Also `os_log` the failure.

### 2.4 Build gating

**Revised after implementation: the extractor compiles in every configuration** — the original `#if DEBUG` decision was made when the approach was assumed to carry private-API risk, and the spike disproved that. The rationale for compiling it everywhere:

- No private selectors are called and no private symbols are linked (pure `Mirror` + type-name matching) — nothing App Store scanning detects, and the pattern ships in store apps today (e.g. SwiftUI-Introspect).
- Extraction executes only inside `beginCapture(in:)`; hosts that gate the inspector at runtime (`Configuration(isEnabled:)`, debug menus) keep it from ever running for end users.
- Every reflective search is node- and depth-bounded, and geometry-by-layer-matching fails toward omission — a changed OS degrades the feature (canary banner), it cannot hang, crash, or misplace.
- The payoff: Release-configuration design reviews (TestFlight internal builds) get full SwiftUI font data instead of the unavailable banner.

## 3. Type Mode

### 3.1 Activation

- New "Aa" button (`textformat` symbol) in the chrome bar, peer of the ruler, `isProminent` when active.
- Tools are mutually exclusive: replace `isMeasurementModeActive` with `activeTool: InspectorTool?` (`.measure` / `.type`); activating one deactivates the other. Toolbar events become `.toolbar(.toolToggled(InspectorTool))`.
- `TypographyCanvasView` mounts as a sibling of `MeasurementCanvasView` (only one is ever mounted), above `AnnotationCanvasView`, with `.id(state.screenID)` so transient state resets per screen. Like measurements, nothing here enters the session.

### 3.2 In the mode

- All `.text` elements draw a thin outline (indigo, to read distinctly against measurement red and annotation styling), denormalized from unit coordinates into the displayed image frame — same math as measurement.
- Tap selects the smallest text element under the finger (reuse the smallest-rect policy from `ElementSpacingCalculator.pressedElement`); repeated taps on overlapping elements cycle, matching annotation-selection convention.
- Selection presents a glass detail card anchored near the element with edge avoidance (same behavior family as the spacing readout menu):
  - **Line 1 (identity):** `GTAmerica-Bold · 19pt`. One row per distinct run font when mixed. System faces may render as `SF Pro Semibold · 17pt` via a small `.SFUI-*` prefix mapping — low priority.
  - **Line 2 (context):** the string, one line, tail-truncated.
  - **Copy affordance:** copies `GTAmerica-Bold 19pt — "Profile Header"`; haptic tick + brief checkmark confirmation.
- Tap outside any element, tap the selected element again, exiting the mode, or switching screens dismisses the card.
- **Extraction-failed element** (`fonts.isEmpty`): outlines and taps normally; card shows the string (if any) with "Font unavailable".
- **Canary tripped** (`fontExtractionUnavailable`): entering type mode shows a single glass banner — "Font extraction isn't available on this iOS version" — instead of N misleading per-element failures. UILabel-sourced elements still work normally.

## 4. Edge Cases & Policies

- **Truncated text:** the extracted string is the full source string; the frame is the drawn frame. Show the full string in the card.
- **Offscreen/clipped text:** the display list contains only drawn content — scrolled-away text is naturally absent, which matches the screenshot the reviewer sees. Elements straddling the capture edge outline and hit-test only their visible portion.
- **Empty or zero-size items:** filter out empty strings and rects below the existing minimum-element threshold.
- **SF Symbols / image glyphs:** not text items in the display list; naturally excluded.
- **Dynamic Type:** fonts arrive post-resolution (`.title2` → `.SFUI-Regular 22pt` verified), so the card reports what was actually rendered at capture time. No style back-mapping in v1.
- **Element cap:** text elements share the existing 600-element walk cap; text elements take priority over containers if the cap is hit.
- **Performance:** bounded BFS (≤40k nodes/hosting view, depth ≤12) ran instantaneously in the spike; capture happens once, before presentation, off the interaction path.

## 5. Fragility Policy

- The extractor is validated against iOS 26.x only. Each new iOS major requires re-running the validation (the spike flow: known fonts rendered → extracted identities compared).
- The canary makes wholesale breakage visible at a glance; the layer walk keeps outlines working regardless.
- Consider a package test that renders `Text` fixtures in a hosting controller under simulator tests and asserts extraction, so OS breakage fails CI rather than a review session.

## 6. Demo App

- Add at least one custom-font text (e.g. Avenir face) to a demo screen so type mode demonstrates non-system extraction.
- Delete `FontSpike.swift` and the temporary `.task` hook in `View_DrawingApp.swift` once extraction is ported into `ScreenCapturer` — the spike is the reference implementation for §2.2.

## 7. Out of Scope (v1) / Future

- Design-token reverse mapping (host-supplied token table naming `bodyM` etc., flagging off-scale sizes) — the natural v2; requires public API for the token table.
- Text color, line height, alignment in the card — line metrics are already reachable (`EncodedFontMetrics`: capHeight/ascender/descender/leading) if wanted later.
- `UITextView` / `UITextField` / `CATextLayer` / `UIButton.Configuration` introspection tiers.
- Persisting font readouts into annotations or the PDF report (deliberately ephemeral, matching measurements).
- Badges-everywhere survey overlay (show all font sizes at once).
