# Font Inspector — Architecture

How typography mode works, why it's built this way, and — most importantly — how to repair it when a future iOS release breaks the SwiftUI extraction. Companion to `FontInspector-SPEC.md`.

## 1. Component Map

All feature code lives in `DesignReviewKit/Sources/DesignReviewKit/FontInspection/`:

| File | Role |
|---|---|
| `CapturedTextElement.swift` | Models: `CapturedTextElement` (unit-space frame + string + fonts) and `FontIdentity` (face/family/size + display formatting) |
| `SwiftUITextExtraction.swift` | `#if DEBUG` reflection extractor for SwiftUI text (see §3) |
| `TextElementCapturer.swift` | Orchestrator: UILabel tier + SwiftUI tier + dedup + canary flag |
| `TypographyCanvasView.swift` | The mode UI: outlines, tap-to-cycle selection, glass font card, copy affordance, unavailable banner |

Touch points in existing code (kept deliberately small):

- `CapturedScreen` — two new stored fields: `textElements`, `fontExtractionUnavailable`.
- `ScreenCapturer.capture(window:)` — one call into `TextElementCapturer`.
- `InspectorViewModel` — `InspectorTool` enum (`.measure` / `.typography`) replaces the measurement boolean; one toolbar event `toolToggled(InspectorTool)` enforces mutual exclusivity.
- `InspectorRootView` — the "Aa" chrome button and the tool-overlay mount switch.
- `AnnotatingState` / `AnnotatingStateBuilder` — passthrough of the two new fields.

## 2. Data Flow

```
host trigger → DesignInspector.beginCapture(in:)
  → ScreenCapturer.capture(window:)            (BEFORE the overlay presents)
      → TextElementCapturer.capture(in:)
          → UILabel walk                        (all builds — nav titles, UIKit hosts)
          → SwiftUITextExtraction.extractTexts  (#if DEBUG — SwiftUI Text)
          → filter / dedupe / cap / normalize to unit coordinates
      → CapturedScreen { textElements, fontExtractionUnavailable }
  → ReviewSession → AnnotatingStateBuilder → AnnotatingState
  → InspectorRootView mounts TypographyCanvasView while activeTool == .typography
```

Everything is harvested **at capture time** — the inspector operates on a frozen
screenshot, so nothing can be queried after presentation. Font readouts are
transient (view-local state, reset per screen via `.id(screenID)`); they never
enter the session, annotations, or PDF, matching the measurement precedent.

## 3. SwiftUI Extraction — Two Phases

The extractor never calls private selectors and links no private symbols. It
uses `Mirror` (public API) over SwiftUI's internal object graph, plus layer
class-name checks. Validated on iOS 26.0.

**Phase 1 — payloads (what the text is).** For every view whose class name
contains `"Hosting"` (this includes `_UIHostingView` and internal hosts like
`NavigationStackHostingController`'s content view), a bounded breadth-first
`Mirror` search locates its `SwiftUI.DisplayList`. The list is parsed
recursively in paint order:

- `effect` items wrap a nested `DisplayList` → recurse.
- `content` items whose value case is `text` carry `(StyledTextContentView, CGSize)`;
  a second bounded search inside finds the stored `NSAttributedString` —
  **public API from here**: `.string` and per-run `.font` attributes (which is
  why mixed-run text reports every font).
- Unknown item kinds → search for nested lists and recurse.

**Phase 2 — geometry (where the text is).** Display-list frames are **not
trusted for position**: inside scroll containers they're in content
coordinates, and the live scroll offset exists only in the platform layer tree
(this was found and fixed during validation — outlines floated ~168pt off
inside a `NavigationStack`+`ScrollView`). Instead, SwiftUI renders each text
into a `CGDrawingLayer`; the extractor collects those layers' window frames in
paint order and matches payload → layer **in order, by exact size**
(±0.5pt; sizes align to pixel thirds). The layer's frame is authoritative —
already scrolled, already transformed.

A payload with no matching layer is dropped (fails toward omission, never
toward a wrong position). A layer with no payload simply isn't a text layer.

### Degradation ladder

1. **Healthy (Debug, supported OS):** full outlines + fonts + strings.
2. **Per-element failure** (attributed string found but no font attribute):
   element still outlines and taps; card shows the string + "Font unavailable".
3. **Wholesale failure** (Release build, or OS broke the reflection): SwiftUI
   elements disappear from typography mode; UILabel-tier elements keep working;
   the **canary** (`fontExtractionUnavailable`) shows one explanatory banner.
   Canary rule: `CGDrawingLayer`s exist in the window but zero SwiftUI texts
   were extracted. Known false positive: a SwiftUI screen whose drawing layers
   are all shapes (no text anywhere) also trips it — harmless, since the mode
   has nothing to inspect there anyway.

## 4. When a Future iOS Breaks It — Repair Playbook

**Symptom:** on a new iOS, typography mode shows the "Font extraction isn't
available…" banner on screens that clearly contain SwiftUI text (the canary
fired), or outlines land in wrong places.

The extraction has exactly four couplings to SwiftUI internals. Check them in
this order — each has a distinct failure signature:

| # | Coupling | Where | Failure signature |
|---|---|---|---|
| 1 | Hosting-view class names contain `"Hosting"` | `hostingViews(under:)` | No graphs found at all → zero texts |
| 2 | The type name `"SwiftUI.DisplayList"` and its `items` property | `displayLists(from:)`, `collectTexts` | Graph search returns nothing, or items don't parse |
| 3 | Item shape: `frame`/`value` properties; case labels `effect`, `content`, `text` | `collectItemTexts` | Lists found but zero text payloads |
| 4 | Text layer class name contains `"CGDrawingLayer"` | `drawingLayerFrames(in:)`, canary | Payloads found but nothing matches → all dropped, canary fires |

**Diagnosis procedure** (this is exactly how the feature was built — recreate
the throwaway harness):

1. Add a temporary debug file to the demo app that renders a few `Text` views
   with known fonts (one system, one custom like `Avenir-Heavy` — the custom
   name doubles as a grep needle).
2. Dump the hosting view's object graph with a recursive `Mirror` walk
   (bounded: ~30k nodes, depth ~9; print `path: typeName = description`,
   following `superclassMirror` too — SwiftUI stores key state in
   superclasses). Search the dump for the needle font name: wherever it
   appears, that's the new home of the resolved font.
3. Walk the layer tree and print layer class names to re-confirm the text
   layer class (coupling 4).
4. Update the four couplings to the new names/shapes. The two bounded BFS
   searches are deliberately name-based rather than path-based so that
   *intermediate* renames (properties between the hosting view and the display
   list) don't matter — only the four couplings above do.
5. Re-validate: extracted (string, font, size) must match the known fixtures,
   including a mixed-run text, a `NavigationStack`+`ScrollView` screen
   (scroll-offset regression — compare outline positions visually, not just
   numerically), and a presented sheet.

**Guard rails already in place for that day:**

- All searches are node- and depth-bounded — a changed OS degrades the
  feature; it cannot hang or crash capture.
- Geometry-by-layer-matching fails toward omission, never wrong placement.
- The canary makes wholesale breakage visible in one glance instead of N
  confusing empty cards.
- Everything is `#if DEBUG`, so a broken OS can never affect a Release build.

## 5. Known Limitations

- `drawingGroup()` / `Canvas`-flattened text rasterizes without per-text
  layers → those texts are dropped (omission).
- Two same-size texts drawn in the same paint order position could in theory
  swap frames; sizes carry sub-point precision, so real collisions are rare
  and bounded to identically-sized siblings.
- UIKit tier covers `UILabel` only (v1 scope): `UITextView`/`UITextField`/
  `CATextLayer`/`UIButton.Configuration` are future tiers.
- The card shows fonts as rendered (post Dynamic Type resolution); it does not
  back-map to text styles or design tokens (future, per spec §7).
