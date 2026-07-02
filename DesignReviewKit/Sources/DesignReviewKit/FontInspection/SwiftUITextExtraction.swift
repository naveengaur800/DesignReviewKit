//
//  SwiftUITextExtraction.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 02/07/2026.
//

import UIKit

/// Recover rendered SwiftUI text — frame, string, and resolved fonts — by
/// pairing the framework's private render graph with its live layer tree.
///
/// Two phases (validated on iOS 26.0):
/// - **Payloads** come from each hosting view's `SwiftUI.DisplayList`: text
///   draws as a `content` item whose value is `text(StyledTextContentView, _)`,
///   and the styled text stores the `NSAttributedString` CoreText actually
///   drew — public API from there on. Items are collected in paint order.
/// - **Geometry** comes from the `CGDrawingLayer`s SwiftUI renders text into.
///   Display-list frames are unreliable across scroll boundaries (they're in
///   content coordinates; the live offset exists only in the layer tree), so
///   each text payload is matched to its drawing layer — in paint order, by
///   exact size, preferring the candidate nearest the payload's approximate
///   position so a same-size shape drawn elsewhere can't steal a text's
///   geometry — and the layer's window frame is authoritative.
///
/// Everything is reached with `Mirror` over stored properties and layer-class
/// name checks. No private selectors are called and no private symbols are
/// linked; the only coupling is to internal type names and shapes, which can
/// change between OS releases. `FontInspector-ARCHITECTURE.md` documents the
/// repair playbook.
///
/// Compiled in every configuration: extraction executes only during capture,
/// every search is budget-bounded, and an OS that changes internals degrades
/// the feature to `CapturedScreen.fontExtractionUnavailable` — it can't hang,
/// crash, or misplace elements.
enum SwiftUITextExtraction {

    /// One rendered text run group, in window coordinates.
    struct ExtractedText {
        let frame: CGRect
        let string: String
        /// One entry per distinct styled run, in run order.
        let fonts: [UIFont]
    }

    /// Bound every reflective search so a changed OS can degrade the feature
    /// but never turn capture into an unbounded crawl.
    private enum SearchLimits {
        static let graphNodeBudget = 40_000
        static let graphDepth = 12
        static let payloadNodeBudget = 5_000
        static let payloadDepth = 10
        static let nestedListLimit = 8
        static let displayListDepth = 40
        static let layerWalkDepth = 50
        static let viewWalkDepth = 50
    }

    /// Matching tolerance between a text item's size and its layer's bounds;
    /// sizes align to pixel thirds, so half a point separates real neighbors.
    private static let sizeTolerance: CGFloat = 0.5

    /// A text payload awaiting its geometry.
    private struct PendingText {
        let size: CGSize
        let string: String
        let fonts: [UIFont]
        /// Display-list position — exact for unscrolled content, offset by the
        /// scroll distance inside scroll containers. Used only to choose
        /// between same-size layer candidates, never as final geometry.
        let approximateCenter: CGPoint
    }

    /// Extract all rendered SwiftUI text under `window`.
    static func extractTexts(in window: UIWindow) -> [ExtractedText] {
        var pending: [PendingText] = []
        for hostingView in hostingViews(under: window) {
            guard let displayList = displayLists(
                from: hostingView,
                nodeBudget: SearchLimits.graphNodeBudget,
                depthLimit: SearchLimits.graphDepth,
                limit: 1
            ).first else { continue }
            var local: [PendingText] = []
            collectTexts(in: displayList, origin: .zero, into: &local, depth: 0)
            pending.append(contentsOf: local.map { text in
                PendingText(
                    size: text.size,
                    string: text.string,
                    fonts: text.fonts,
                    approximateCenter: window.convert(text.approximateCenter, from: hostingView)
                )
            })
        }

        // Pair payloads with layers in paint order. Candidates must match the
        // payload's size; among them the layer nearest the payload's
        // approximate position wins, so a same-size shape drawn elsewhere
        // can't steal a text's geometry.
        var layers = drawingLayerFrames(in: window).map { (frame: $0, isConsumed: false) }
        var results: [ExtractedText] = []
        for text in pending {
            let candidates = layers.indices.filter { index in
                !layers[index].isConsumed
                    && abs(layers[index].frame.width - text.size.width) < Self.sizeTolerance
                    && abs(layers[index].frame.height - text.size.height) < Self.sizeTolerance
            }
            guard let nearest = candidates.min(by: { lhs, rhs in
                squaredDistance(from: layers[lhs].frame, to: text.approximateCenter)
                    < squaredDistance(from: layers[rhs].frame, to: text.approximateCenter)
            }) else { continue }
            layers[nearest].isConsumed = true
            results.append(ExtractedText(frame: layers[nearest].frame, string: text.string, fonts: text.fonts))
        }
        return results
    }

    private static func squaredDistance(from frame: CGRect, to point: CGPoint) -> CGFloat {
        let deltaX = frame.midX - point.x
        let deltaY = frame.midY - point.y
        return deltaX * deltaX + deltaY * deltaY
    }

    // MARK: - Hosting Views

    /// Views owning a render graph: `_UIHostingView` plus internal hosts such as
    /// `NavigationStackHostingController`'s content view, where navigation
    /// destinations actually render. Hidden subtrees are skipped — a hidden
    /// host's payloads have no visible layers and would steal same-size
    /// candidates from visible text.
    private static func hostingViews(under root: UIView) -> [UIView] {
        var matches: [UIView] = []
        func walk(_ view: UIView, depth: Int) {
            guard depth < SearchLimits.viewWalkDepth, !view.isHidden, view.alpha > 0.01 else { return }
            if String(reflecting: type(of: view)).contains("Hosting") {
                matches.append(view)
            }
            for subview in view.subviews {
                walk(subview, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return matches
    }

    // MARK: - Payload Collection

    /// Collect text payloads from a `SwiftUI.DisplayList` in paint order,
    /// accumulating item origins into the approximate position heuristic.
    private static func collectTexts(in list: Any, origin: CGPoint, into pending: inout [PendingText], depth: Int) {
        guard depth < SearchLimits.displayListDepth else { return }
        guard let items = Mirror(reflecting: list).children.first(where: { $0.label == "items" })?.value else { return }
        for element in Mirror(reflecting: items).children {
            collectItemTexts(element.value, origin: origin, into: &pending, depth: depth)
        }
    }

    private static func collectItemTexts(_ item: Any, origin: CGPoint, into pending: inout [PendingText], depth: Int) {
        let mirror = Mirror(reflecting: item)
        guard let frame = mirror.children.first(where: { $0.label == "frame" })?.value as? CGRect,
              let value = mirror.children.first(where: { $0.label == "value" })?.value,
              let itemCase = Mirror(reflecting: value).children.first
        else { return }

        let itemOrigin = CGPoint(x: origin.x + frame.origin.x, y: origin.y + frame.origin.y)

        switch itemCase.label {
        case "effect":
            // (Effect, DisplayList) — descend into the nested list.
            for tupleChild in Mirror(reflecting: itemCase.value).children
            where String(reflecting: type(of: tupleChild.value)) == "SwiftUI.DisplayList" {
                collectTexts(in: tupleChild.value, origin: itemOrigin, into: &pending, depth: depth + 1)
            }

        case "content":
            guard let contentValue = Mirror(reflecting: itemCase.value).children
                .first(where: { $0.label == "value" })?.value,
                let contentCase = Mirror(reflecting: contentValue).children.first
            else { return }
            if contentCase.label == "text" {
                let center = CGPoint(
                    x: itemOrigin.x + frame.size.width / 2,
                    y: itemOrigin.y + frame.size.height / 2
                )
                appendText(from: contentCase.value, size: frame.size, center: center, into: &pending)
            }

        default:
            // Unknown item kinds (clips, transforms, platform groups) can still
            // wrap lists of drawable children — recurse into any found nearby.
            for nested in displayLists(
                from: itemCase.value,
                nodeBudget: SearchLimits.payloadNodeBudget,
                depthLimit: SearchLimits.payloadDepth,
                limit: SearchLimits.nestedListLimit
            ) {
                collectTexts(in: nested, origin: itemOrigin, into: &pending, depth: depth + 1)
            }
        }
    }

    /// Pull string and per-run fonts out of a `text(StyledTextContentView, _)`
    /// payload via its stored `NSAttributedString`.
    private static func appendText(from payload: Any, size: CGSize, center: CGPoint, into pending: inout [PendingText]) {
        let attributedStrings = searchStoredValues(
            from: payload,
            nodeBudget: SearchLimits.payloadNodeBudget,
            depthLimit: SearchLimits.payloadDepth,
            limit: 1
        ) { $0 is NSAttributedString }
        guard let attributed = attributedStrings.first as? NSAttributedString else { return }

        pending.append(PendingText(
            size: size,
            string: attributed.string,
            fonts: attributed.distinctRunFonts,
            approximateCenter: center
        ))
    }

    // MARK: - Layer Geometry

    /// Window frames of SwiftUI's text drawing layers, in paint order.
    private static func drawingLayerFrames(in window: UIWindow) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ layer: CALayer, depth: Int) {
            guard depth < SearchLimits.layerWalkDepth else { return }
            for sublayer in layer.sublayers ?? [] {
                guard !sublayer.isHidden, sublayer.opacity > 0.05 else { continue }
                if String(reflecting: type(of: sublayer)).contains("CGDrawingLayer") {
                    frames.append(window.layer.convert(sublayer.bounds, from: sublayer))
                }
                walk(sublayer, depth: depth + 1)
            }
        }
        walk(window.layer, depth: 0)
        return frames
    }

    // MARK: - Reflective Search

    /// Values typed `SwiftUI.DisplayList` reachable from `root`'s stored properties.
    private static func displayLists(from root: Any, nodeBudget: Int, depthLimit: Int, limit: Int) -> [Any] {
        searchStoredValues(from: root, nodeBudget: nodeBudget, depthLimit: depthLimit, limit: limit) {
            String(reflecting: type(of: $0)) == "SwiftUI.DisplayList"
        }
    }

    /// Breadth-first `Mirror` search over stored properties (following
    /// superclass storage), cycle-guarded and bounded by node and depth
    /// budgets. Matched values are collected without being expanded. Views
    /// other than `root` are never expanded either, so a search from one
    /// hosting view can't tunnel into another's render graph.
    private static func searchStoredValues(
        from root: Any,
        nodeBudget: Int,
        depthLimit: Int,
        limit: Int,
        matches: (Any) -> Bool
    ) -> [Any] {
        var found: [Any] = []
        var queue: [(value: Any, depth: Int)] = [(root, 0)]
        var visited = Set<ObjectIdentifier>()
        var index = 0

        while index < queue.count, index < nodeBudget, found.count < limit {
            let (value, depth) = queue[index]
            index += 1

            if matches(value) {
                found.append(value)
                continue
            }
            guard depth < depthLimit else { continue }
            if let view = value as? UIView, view !== (root as? UIView) {
                continue
            }
            if type(of: value) is AnyClass, let object = value as? AnyObject {
                let identifier = ObjectIdentifier(object)
                guard visited.insert(identifier).inserted else { continue }
            }

            // Cap the queue as well as processed nodes: one reflected node
            // holding a huge collection must not balloon memory before the
            // processing budget bites.
            var mirror: Mirror? = Mirror(reflecting: value)
            while let current = mirror, queue.count < nodeBudget {
                for child in current.children {
                    guard queue.count < nodeBudget else { break }
                    queue.append((child.value, depth + 1))
                }
                mirror = current.superclassMirror
            }
        }
        return found
    }
}
