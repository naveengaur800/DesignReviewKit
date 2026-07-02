//
//  AccessibilityProbe.swift
//  View Drawing
//
//  Created by Naveen Gaur on 03/07/2026.
//

import UIKit

/// One accessibility element recovered by the probe, in the exact shape the
/// real `CapturedAccessibilityElement` will take (AccessibilityInspector-SPEC §4.2).
struct ProbedNode: Identifiable {
    let id = UUID()
    let label: String?
    let value: String?
    let hint: String?
    let identifier: String?
    let traitNames: [String]
    let sourceClass: String
    /// Whether the node is a synthesized `UIAccessibilityElement` (the SwiftUI
    /// bridge) rather than a backing `UIView`.
    let isSynthesizedElement: Bool
    let frame: CGRect

    var hasLabel: Bool { !(label ?? "").isEmpty }
}

/// Walk a view subtree the way assistive technology does — using only the
/// public `UIAccessibility` informal protocol — and collect every element.
///
/// This is the load-bearing spike: with the automation runtime off, a SwiftUI
/// host returns no elements here; with it on, the same walk recovers them.
@MainActor
struct AccessibilityProbe {

    private let maximumDepth = 60

    /// Collect the accessibility elements under `root` in traversal order.
    func walk(_ root: UIView) -> [ProbedNode] {
        var nodes: [ProbedNode] = []
        var visited = Set<ObjectIdentifier>()
        traverse(root, into: &nodes, visited: &visited, depth: 0)
        return nodes
    }

    private func traverse(
        _ object: NSObject,
        into nodes: inout [ProbedNode],
        visited: inout Set<ObjectIdentifier>,
        depth: Int
    ) {
        guard depth < maximumDepth, visited.insert(ObjectIdentifier(object)).inserted else { return }

        // Leaf: an object that declares itself an element exposes no children.
        if object.isAccessibilityElement {
            nodes.append(makeNode(object))
            return
        }

        // Container, explicit array — assistive tech uses these, not subviews.
        if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
            for element in elements {
                traverse(element, into: &nodes, visited: &visited, depth: depth + 1)
            }
            return
        }

        // Container, count/index protocol.
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                guard let element = object.accessibilityElement(at: index) as? NSObject else { continue }
                traverse(element, into: &nodes, visited: &visited, depth: depth + 1)
            }
            return
        }

        // Plain view with no accessibility payload — descend into subviews.
        if let view = object as? UIView {
            for subview in view.subviews where !subview.isHidden && subview.alpha > 0.01 {
                traverse(subview, into: &nodes, visited: &visited, depth: depth + 1)
            }
        }
    }

    private func makeNode(_ object: NSObject) -> ProbedNode {
        ProbedNode(
            label: object.accessibilityLabel,
            value: object.accessibilityValue,
            hint: object.accessibilityHint,
            identifier: identifier(of: object),
            traitNames: AccessibilityTraitDecoder.names(for: object.accessibilityTraits),
            sourceClass: String(describing: type(of: object)),
            isSynthesizedElement: !(object is UIView),
            frame: object.accessibilityFrame
        )
    }

    /// Read the accessibility identifier.
    ///
    /// SwiftUI's `.accessibilityIdentifier` does not surface through the formal
    /// `UIAccessibilityIdentification` cast on its bridged `AccessibilityNode`
    /// (that returns nil) — it is only reachable via KVC. UIKit views answer the
    /// protocol directly. Try the protocol first, then fall back to KVC.
    private func identifier(of object: NSObject) -> String? {
        let viaProtocol = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
        let viaKVC = object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
            ? object.value(forKey: "accessibilityIdentifier") as? String
            : nil
        return [viaProtocol, viaKVC].compactMap { $0 }.first { !$0.isEmpty }
    }
}

/// Map the public `UIAccessibilityTraits` bits to VoiceOver-facing names.
enum AccessibilityTraitDecoder {

    private static let table: [(UIAccessibilityTraits, String)] = [
        (.button, "Button"),
        (.link, "Link"),
        (.header, "Header"),
        (.selected, "Selected"),
        (.notEnabled, "Not Enabled"),
        (.image, "Image"),
        (.staticText, "Static Text"),
        (.searchField, "Search Field"),
        (.adjustable, "Adjustable"),
        (.summaryElement, "Summary"),
        (.updatesFrequently, "Updates Frequently"),
        (.startsMediaSession, "Starts Media Session"),
        (.allowsDirectInteraction, "Direct Interaction"),
        (.causesPageTurn, "Causes Page Turn"),
        (.keyboardKey, "Keyboard Key"),
        (.playsSound, "Plays Sound"),
        (.tabBar, "Tab Bar"),
    ]

    /// Readable trait names contained in `traits`, in table order.
    static func names(for traits: UIAccessibilityTraits) -> [String] {
        table.filter { traits.contains($0.0) }.map { $0.1 }
    }
}
