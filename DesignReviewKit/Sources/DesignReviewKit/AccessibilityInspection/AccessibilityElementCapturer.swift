//
//  AccessibilityElementCapturer.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 03/07/2026.
//

import UIKit

/// Collect the window's accessibility elements at capture time, walking the
/// public `UIAccessibility` informal protocol in the order assistive technology
/// visits them.
///
/// The tree only materializes while an assistive technology — or the host's
/// runtime enabler (`DesignInspector.Configuration.accessibilityRuntimeEnabler`)
/// — is active. When it isn't, the walk finds nothing and the canary trips so
/// accessibility mode explains itself instead of showing an empty screen.
struct AccessibilityElementCapturer {

    /// Accessibility capture output for one screen.
    struct Capture {
        let elements: [CapturedAccessibilityElement]
        /// Whether SwiftUI drew content but the accessibility tree was empty —
        /// the runtime wasn't materialized this capture.
        let treeUnavailable: Bool
    }

    /// Plenty for any real screen while bounding session memory.
    private static let maximumElementCount = 300
    private static let maximumWalkDepth = 60
    private static let minimumElementSide: CGFloat = 1

    /// Capture the window's accessibility elements in unit coordinates.
    func capture(in window: UIWindow) -> Capture {
        let windowBounds = window.bounds
        guard windowBounds.width > 0, windowBounds.height > 0 else {
            return Capture(elements: [], treeUnavailable: false)
        }

        var visited = Set<ObjectIdentifier>()
        var rawElements: [(frame: CGRect, object: NSObject)] = []
        collect(from: window, window: window, depth: 0, visited: &visited, into: &rawElements)

        var elements: [CapturedAccessibilityElement] = []
        var seenKeys = Set<String>()
        for raw in rawElements {
            guard elements.count < Self.maximumElementCount else { break }
            let frame = raw.frame
            guard frame.intersects(windowBounds),
                  frame.width >= Self.minimumElementSide,
                  frame.height >= Self.minimumElementSide else { continue }

            let key = "\(Int(frame.minX.rounded()))|\(Int(frame.minY.rounded()))|\(Int(frame.width.rounded()))|\(Int(frame.height.rounded()))"
            guard seenKeys.insert(key).inserted else { continue }

            elements.append(makeElement(raw.object, frame: frame, windowBounds: windowBounds))
        }

        // Canary: content was drawn (SwiftUI drawing layers exist) but the walk
        // recovered no elements — the accessibility runtime wasn't materialized.
        let treeUnavailable = elements.isEmpty
            && containsSwiftUIDrawingLayers(window.layer, depth: 0)
        return Capture(elements: elements, treeUnavailable: treeUnavailable)
    }

    // MARK: - Walk

    /// Visit elements the way assistive technology does: a leaf that declares
    /// itself an element, else the explicit `accessibilityElements`, else the
    /// count/index container protocol, else recurse into subviews. Element order
    /// is preserved as VoiceOver's flick order.
    private func collect(
        from object: NSObject,
        window: UIWindow,
        depth: Int,
        visited: inout Set<ObjectIdentifier>,
        into rawElements: inout [(frame: CGRect, object: NSObject)]
    ) {
        guard depth < Self.maximumWalkDepth,
              rawElements.count < Self.maximumElementCount,
              visited.insert(ObjectIdentifier(object)).inserted else { return }

        if let view = object as? UIView, view.isHidden || view.alpha <= 0.01 { return }

        // A container can hide the elements it vends; VoiceOver skips them.
        if object.accessibilityElementsHidden { return }

        if object.isAccessibilityElement {
            let frame = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
            rawElements.append((frame, object))
            return
        }

        if let elements = object.accessibilityElements, !elements.isEmpty {
            for case let element as NSObject in elements {
                collect(from: element, window: window, depth: depth + 1, visited: &visited, into: &rawElements)
            }
            return
        }

        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                guard let element = object.accessibilityElement(at: index) as? NSObject else { continue }
                collect(from: element, window: window, depth: depth + 1, visited: &visited, into: &rawElements)
            }
            return
        }

        if let view = object as? UIView {
            for subview in view.subviews {
                collect(from: subview, window: window, depth: depth + 1, visited: &visited, into: &rawElements)
            }
        }
    }

    // MARK: - Element Construction

    private func makeElement(
        _ object: NSObject,
        frame: CGRect,
        windowBounds: CGRect
    ) -> CapturedAccessibilityElement {
        let traits = object.accessibilityTraits
        let label = cleaned(object.accessibilityLabel)

        var flags: Set<CapturedAccessibilityElement.Flag> = []
        if label == nil, AccessibilityTraitDecoder.expectsLabel(traits) {
            flags.insert(.missingLabel)
        }

        let value = cleaned(object.accessibilityValue)
        let hint = cleaned(object.accessibilityHint)

        return CapturedAccessibilityElement(
            id: UUID(),
            normalizedRect: frame.normalized(in: windowBounds),
            label: label,
            value: value,
            hint: hint,
            identifier: identifier(of: object),
            traitNames: AccessibilityTraitDecoder.names(for: traits),
            sourceClass: String(describing: type(of: object)),
            voiceOver: VoiceOverUtteranceComposer.compose(
                label: label,
                value: value,
                hint: hint,
                traits: traits
            ),
            flags: flags
        )
    }

    /// SwiftUI's `.accessibilityIdentifier` surfaces only via KVC on its bridged
    /// `AccessibilityNode` — the `UIAccessibilityIdentification` cast returns nil
    /// there — while UIKit views answer the protocol directly. Try the protocol,
    /// then fall back to KVC.
    private func identifier(of object: NSObject) -> String? {
        if let identifier = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier,
           !identifier.isEmpty {
            return identifier
        }
        guard object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
              let identifier = object.value(forKey: "accessibilityIdentifier") as? String,
              !identifier.isEmpty else { return nil }
        return identifier
    }

    /// Trimmed string, or `nil` when empty — absence is reported explicitly, never
    /// as a blank.
    private func cleaned(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Canary

    /// Whether SwiftUI drawing layers are present — content was rendered, so an
    /// empty accessibility walk means the runtime wasn't materialized rather than
    /// the screen being genuinely empty. Mirrors the typography-mode canary.
    private func containsSwiftUIDrawingLayers(_ layer: CALayer, depth: Int) -> Bool {
        guard depth < Self.maximumWalkDepth else { return false }
        for sublayer in layer.sublayers ?? [] {
            if String(reflecting: type(of: sublayer)).contains("CGDrawingLayer") {
                return true
            }
            if containsSwiftUIDrawingLayers(sublayer, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}
