# Accessibility Inspector — Specification

Tap-to-inspect accessibility properties in DesignReviewKit: switch to
accessibility mode on a frozen capture, tap any element, and read exactly what
developers set — identifier, label, value, hint, traits — with factual flags
where required properties are missing.

> **Status: BUILT (2026-07-03).** Shipped into DesignReviewKit as
> `InspectorTool.accessibility` — new `AccessibilityInspection/` group
> (`CapturedAccessibilityElement`, `AccessibilityElementCapturer`,
> `AccessibilityCanvasView`), two fields on `CapturedScreen`, a chrome button,
> and the `Configuration.accessibilityRuntimeEnabler` hook. Verified on the iOS
> 26 simulator (outlines + card + flags + copy). Decisions locked 2026-07-02;
> host-enabler amendment + simulator spike 2026-07-03 (§7.1). Physical-device
> enabler re-run (§7.2) is the one remaining check. Earlier drafts scoped a
> VoiceOver playback simulator; that is **descoped** (see §2).

---

## 1. Summary of Decisions

| Area | Decision |
|---|---|
| Feature | Tap-to-inspect raw accessibility properties on the frozen capture. No VoiceOver simulation of any kind |
| Card contents | Core set: `accessibilityIdentifier`, label, value, hint, traits (as readable names) |
| Flagging | Factual missing-property flags (empty label, unlabeled image/button). No coverage heuristics |
| Tree access | **Package is public API only — hard constraint.** No `dlopen`/`dlsym` of private symbols, no private selectors, no private frameworks in DesignReviewKit |
| Host enabler | Hosts *may* add a build-config-gated enabler file at their composition root (§3.1); the package neither contains nor references it. Demo app carries the reference implementation |
| Runtime enablement | Otherwise reviewer-side, needed only at the instant of capture (§3); canary + guidance banner when absent |
| Placement | Third `InspectorTool` mode in DesignReviewKit — no new package |
| Session/PDF | Readouts transient (typography precedent); accessibility data never enters annotations or PDF |
| iOS target | 17, matching the package |

## 2. Scope — What This Is and Isn't

**Is:** typography mode's shape with an accessibility harvest. Outline the
captured elements, tap to cycle overlapping ones, read a glass card of raw
properties, copy values, see factual flags.

**Isn't (descoped from the original idea, in order of decision):**

- VoiceOver speech playback, auto-sweep, step navigation, order badges — the
  whole simulation layer. *Why:* the spoken sentence and swipe order are
  composed inside the system accessibility server; re-implementing them means
  a permanent parity-verification burden for a secondary need. The primary
  need is seeing the properties.
- A composed "VoiceOver reads: …" text line. *Why:* user chose raw
  properties as the contract — print what developers set, interpret nothing.
- VO navigation index / container context ("2 of 5"), custom actions, source
  view class. *Why:* not selected for the card; the ordering walk was the
  last semi-hard implementation piece and nothing needs it now.
- Visible-but-uncovered content audit (content VO can't reach at all).
  *Why:* needs a false-positive-prone heuristic; revisit after v1 proves out.

## 3. Tree Access — the Public-API Reality

iOS materializes accessibility data lazily. With no assistive technology
attached: derived UIKit attributes (a button's label from its title) may be
absent, and SwiftUI's bridged accessibility nodes typically don't exist at
all — `ScreenCapturer` already documents this. The only in-process switch is
a private function (`_AXSSetAutomationEnabled`), which is **ruled out** by
the no-private-API constraint. Apple's sanctioned audit API
(`performAccessibilityAudit`) lives in XCUITest, out of process.

**The architecture absorbs this.** Capture is frozen: the accessibility
runtime must be live only for the instant `ScreenCapturer` runs — never
while reviewing. So enablement is a reviewer-side step, not a code problem:

| Flow | Cost | Certainty |
|---|---|---|
| Host app includes the opt-in enabler (§3.1) | One file in the host, gated to internal build configs | Simulator: proven industry-wide for years. Device + launch-vs-lazy timing: §7 spike |
| Accessibility Shortcut → VoiceOver on → capture (shake) → VoiceOver off → review | Two triple-clicks per capture batch | **Guaranteed** — VO is the canonical AX client; its cursor draws in a system window, so captures stay clean |
| Full Keyboard Access enabled once (no keyboard paired → no visible effect) | One Settings toggle, ever | Candidate — §7 spike |
| Speak Screen enabled once (acts only when invoked) | One Settings toggle, ever | Candidate — §7 spike |
| Xcode Accessibility Inspector attached | Tethered desk workflow | Works, but not a phone-in-hand flow |
| Nothing enabled | — | Explicitly-set UIKit properties only; SwiftUI screens likely empty → banner |

**Canary:** `accessibilityTreeUnavailable` on `CapturedScreen` — set when the
walk finds no accessibility elements while SwiftUI drawing layers exist
(reuse the typography canary's layer detection). Semantics differ from
`fontExtractionUnavailable`: this is not "the OS broke us," it's "the tree
wasn't materialized," and the banner says how to fix it — naming whichever
flow the §7 spike validates as cheapest.

### 3.1 Host-Side Enabler (opt-in, outside the package)

The private automation switch (`_AXSSetAutomationEnabled`) stays out of
DesignReviewKit, but hosts may flip it themselves — the package can't tell
*who* materialized the tree and doesn't care; the canary simply never trips.

- One file in the **app target**, at the composition root where the host
  already creates `DesignInspector`; call `enable()` once at launch, before
  the first capture.
- Gate on a **host-defined compilation condition** (e.g. `DESIGN_REVIEW` in
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS`), applied only to internal build
  configurations and never to distributed ones. Do **not** gate on
  `#if DEBUG` inside the package: SPM maps custom-named host configurations
  to the package's *release* mode, so package-side `DEBUG` code silently
  compiles out in hosts with custom schemes — the reason this file must live
  host-side to begin with.
- Guarded `dlopen`/`dlsym` with graceful `return` on failure — a future OS
  removing the symbol degrades to the §3 banner flows, never a crash.
- The View Drawing demo app carries the reference implementation.

Reliability record, for the honest trade-off: the identical mechanism has
shipped in KIF (~2013), EarlGrey, and AccessibilitySnapshot to date —
simulator-proven industry-wide with only brief per-OS-release hiccups.
Physical-device behavior and lazy (first-capture) versus launch-time
enablement are the unproven parts; both are §7 spike items.

## 4. Architecture

All feature code in `DesignReviewKit/Sources/DesignReviewKit/AccessibilityInspection/`:

| File | Role |
|---|---|
| `CapturedAccessibilityElement.swift` | Sendable value model: unit-space frame + core properties + flags |
| `AccessibilityElementCapturer.swift` | Public-API walk of the window's accessibility hierarchy at capture time; dedupe; cap; canary |
| `AccessibilityCanvasView.swift` | Mode UI: outlines, flag badges, tap-to-cycle, glass property card, banner |

Touch points in existing code (typography precedent, kept deliberately small):

- `CapturedScreen` — two new stored fields: `accessibilityElements`,
  `accessibilityTreeUnavailable`.
- `ScreenCapturer.capture(window:)` — one call into `AccessibilityElementCapturer`
  (before the overlay presents, so the inspector never pollutes its own tree).
- `InspectorViewModel.InspectorTool` — new case `.accessibility`; existing
  `toolToggled` mutual exclusivity covers it for free.
- `InspectorRootView` — toolbar button (SF Symbol `accessibility`), mount switch.
- `AnnotatingState` / `AnnotatingStateBuilder` — passthrough of the two fields.

### 4.1 Data Flow

```
host trigger → DesignInspector.beginCapture(in:)
  → ScreenCapturer.capture(window:)                (BEFORE the overlay presents)
      → AccessibilityElementCapturer.capture(in:)
          → walk: accessibilityElements array → count/at container protocol
            → view recursion for isAccessibilityElement views
            → honor accessibilityElementsHidden, accessibilityViewIsModal,
              isHidden / alpha
          → read core properties; compute flags
          → convert accessibilityFrame (screen coords → window → unit space)
          → dedupe, cap at 300 (text-element precedent)
      → CapturedScreen { accessibilityElements, accessibilityTreeUnavailable }
  → AnnotatingState → InspectorRootView mounts AccessibilityCanvasView
    while activeTool == .accessibility
```

Everything is harvested at capture time; the frozen model never re-queries
the app. Readouts are view-local and reset per screen via `.id(screenID)`,
matching typography.

### 4.2 `CapturedAccessibilityElement`

- `id: UUID`, `normalizedFrame: CGRect`
- `identifier: String?` — `accessibilityIdentifier`. **Read via KVC**, not the
  `UIAccessibilityIdentification` cast: SwiftUI's `.accessibilityIdentifier`
  does not surface through that protocol on its bridged `AccessibilityNode`
  (the cast returns nil), but `value(forKey: "accessibilityIdentifier")`
  recovers it. UIKit views answer the protocol directly. Verified 2026-07-03 in
  the demo (`.accessibilityIdentifier("profile_follow_button")` → nil via
  protocol, recovered via KVC). Try protocol first, fall back to KVC.
- `label: String?`, `value: String?`, `hint: String?` — optionals, never
  sentinel-filled; the card renders absence explicitly
- `traitNames: [String]` — readable names mapped from the public
  `UIAccessibilityTraits` bits ("Button", "Header", "Selected", "Not Enabled",
  "Image", "Link", "Adjustable", "Search Field", "Static Text", "Tab Bar",
  "Toggle Button", …); unknown future bits render as "Unknown (bit N)" rather
  than disappearing
- `flags: Set<Flag>` — factual findings computed at capture:
  - `.missingLabel` — interactive or image element with empty/nil label
  - `.unlabeledButton` — `.button` trait without label

  Note (spike §7): a **decorative** SwiftUI `Image` with no label is not in the
  accessibility tree at all — VoiceOver skips it, so the walk never sees it and
  there is nothing to flag. An `.unlabeledImage` flag would therefore rarely
  fire; genuinely detecting "an image a user can see but VO can't" is the
  deferred coverage-audit heuristic (§10), not a per-element flag. Dropped
  `.unlabeledImage` from v1 for this reason.

### 4.3 Card & Canvas UX

- Toolbar gains the accessibility button; `toolToggled(.accessibility)`
  enforces mutual exclusivity with measure/typography.
- Element outlines over the frozen capture; flagged elements get a visually
  distinct outline plus a small badge.
- Tap to select; tap again to cycle overlapping elements (typography
  interaction, same implementation pattern).
- Glass card (typography card visual language): one row per property with
  copy affordance; absent properties show an explicit em-dash — absence is a
  finding, never hidden. Flags render as labeled callouts on the card.
- Canary banner replaces the empty canvas when `accessibilityTreeUnavailable`,
  with the enablement guidance from §3.

## 5. Failure & Degraded Modes

| Condition | Behavior |
|---|---|
| Tree not materialized (no AX client at capture) | Canary → banner with the enablement flow; partial data (explicit UIKit properties) still shown |
| Element with every property nil | Card renders with all em-dashes + `.missingLabel` flag when interactive — never silently skipped |
| Future iOS changes the container protocol behavior | Walk degrades to whatever tiers still answer; canary catches wholesale emptiness; ARCHITECTURE doc gets a repair guide (FontInspector precedent) |
| Real VoiceOver running while reviewing | No conflict — the inspector plays no audio and owns no gestures beyond taps |

## 6. Testing

- Unit: trait-bit → name mapping (including unknown-bit rendering); flag
  rules; capturer on synthetic UIKit hierarchies with explicitly-set
  properties (no runtime enablement needed in tests); canary logic; frame
  normalization from screen coordinate space.
- Manual reference screens in the View Drawing demo app: labeled/unlabeled
  buttons and images, toggles, headers, explicit `accessibilityElements`
  containers, hidden elements, a modal sheet, a SwiftUI-only screen (canary
  path), a UIKit-labels screen (no-enablement path).

## 7. Pre-Implementation Spike

### 7.1 Results — iOS 26 Simulator (run 2026-07-03)

Harness: `View Drawing/Spike/` in the demo app (launch `-SpikeMode 1`, plus
`-SpikeForceOff 1` / `-SpikeEnableAXAtLaunch 1`). It walks an isolated
`UIHostingController` subtree of representative SwiftUI content using only the
public `UIAccessibility` informal protocol, under forced runtime states.

| Runtime state at capture | SwiftUI elements recovered |
|---|---|
| **Forced OFF** (`_AXSSetAutomationEnabled(0)`) | **0 of 7** |
| **Lazy enable** (off → `enableAutomation()` mid-session) | **7 of 7** |
| **Enabled at launch** | **7 of 7** (from the first walk) |

Conclusions:

- **The premise holds.** With the runtime genuinely off, the public-API walk
  recovers *nothing* from SwiftUI — 0 elements. Public API alone is
  insufficient; the enabler is necessary for SwiftUI coverage.
- **The host enabler is sufficient — and works lazily.** One call to
  `enableAutomation()` mid-session materialized the full tree (7/7). No
  launch-time requirement, so `DesignInspector.beginCapture` can trigger the
  host hook immediately before capture; the reviewer needs no Settings toggle
  and no VoiceOver.
- **Recovered data is high fidelity.** Labels (derived *and* explicit), the
  switch's `value=1`, the adjustable's `value="4 stars"` + hint, and traits
  (Static Text / Button / Image / Adjustable) all came through correctly, as
  SwiftUI `AccessibilityNode` elements.
- **The flag was set daemon-side and persists across launches** (matching
  KIF's atexit-reset), and the `_AXSAutomationEnabled` getter can read stale;
  the spike pins state explicitly per launch to measure cleanly. Production
  code should treat the getter as advisory.

Two behaviors the real capturer must handle, surfaced by the spike:

- A **decorative unlabeled `Image` is absent from the tree** (VoiceOver skips
  it) — informs the §4.2 flag change.
- **SwiftUI can emit multiple elements per control** (the `Toggle` produced a
  group node *and* a switch node, both labeled "Notifications") — dedup and
  labeling must expect this.

### 7.2 Still Open — Physical Device

No device was attached at spike time (both iPhones showed unavailable), so the
**one unverified item** is whether `dlopen`/`_AXSSetAutomationEnabled` behaves
the same on real hardware — historically the shakiest part (simulator has
always exposed accessibility more readily). Before shipping, run the same
harness on a device:

1. Does `enableAutomation()` return true and materialize SwiftUI nodes on
   device, lazily and at launch?
2. Fallback if not: which low-impact system toggle (Full Keyboard Access,
   Speak Screen) materializes the tree with zero private API?
3. UIKit-only baseline: which properties are readable with nothing enabled?

The winning flow's instructions become the §3 banner text; findings land in an
`AccessibilityInspector-ARCHITECTURE.md` repair-guide section (FontInspector
precedent). The spike harness stays in the demo app for exactly this re-run.

## 8. Decision Trail

Recorded so future readers know what was considered and why it's absent:

- **VoiceOver playback simulator** — descoped; system-composed speech/order
  can't be read via any public API, only re-implemented (a permanent parity
  burden). Prior art: cashapp/AccessibilitySnapshot re-implements it and
  still requires a private enabler.
- **Private AX-runtime enabler** (`dlopen` + `_AXSSetAutomationEnabled`) —
  **rejected inside the package** (hard constraint: DesignReviewKit contains
  no private API). Amended 2026-07-03: hosts may opt in with their own
  composition-root file (§3.1). Package-shipped `#if DEBUG` gating was also
  rejected on mechanics: SPM builds packages in release mode under
  custom-named host configurations, so the gate would silently compile out
  in exactly the work apps that need it.
- **Mirror-based SwiftUI extraction** (FontInspector approach) — rejected:
  accessibility resolution happens in SwiftUI's attribute graph only when an
  AX client is attached; Mirror would see unresolved modifiers and force a
  re-implementation of SwiftUI's semantics.
- **AccessibilitySnapshot as dependency/vendored code** — moot after the
  playback descope; nothing left needs its composition rules.
- **Separate `AccessibilityReviewKit` package** — rejected: the journey is
  one review gesture; typography set the tool-mode precedent; extract a
  shared core only when a second consumer exists.
- **PDF accessibility appendix** — deferred, matching typography's
  transient-readout precedent.
