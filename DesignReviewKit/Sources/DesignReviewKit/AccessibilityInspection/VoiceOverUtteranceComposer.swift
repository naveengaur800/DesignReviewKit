//
//  VoiceOverUtteranceComposer.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 03/07/2026.
//

import UIKit

/// What VoiceOver would speak for one element: the primary announcement and the
/// guidance spoken after a pause.
nonisolated struct VoiceOverUtterance: Sendable, Equatable {

    /// Label, value, and trait words — the sentence VoiceOver leads with.
    let description: String

    /// Guidance spoken after a pause: the custom hint plus any trait-injected
    /// hint (e.g. the adjustable swipe hint). `nil` when there is none.
    let hint: String?

    var isEmpty: Bool {
        description.isEmpty && (hint ?? "").isEmpty
    }

    /// One-line form for display and copy, hint separated by an em dash.
    var spoken: String {
        guard let hint, !hint.isEmpty else { return description }
        return description.isEmpty ? hint : "\(description) — \(hint)"
    }
}

/// Compose a `VoiceOverUtterance` from an element's raw accessibility properties,
/// applying VoiceOver's composition rules for the common trait set.
///
/// Scope (Tier 1): standalone-element wording — label, value, state and role
/// trait words, and hints. Container context ("2 of 5", "Tab 1 of 3", list and
/// landmark boundaries) is **not** composed here; that needs capture-time
/// grouping detection and is deliberately out of scope. Rules and phrasing follow
/// Apple's documented behavior and cross-check against cashapp/AccessibilitySnapshot.
nonisolated enum VoiceOverUtteranceComposer {

    static func compose(
        label: String?,
        value: String?,
        hint: String?,
        traits: UIAccessibilityTraits
    ) -> VoiceOverUtterance {
        var spokenParts: [String] = []

        // Label leads, value follows after a pause — VoiceOver reads both.
        var leading = label ?? ""
        if let value, !value.isEmpty {
            leading = leading.isEmpty ? value : "\(leading), \(value)"
        }
        if !leading.isEmpty {
            spokenParts.append(leading)
        }

        // State words, then role words — the order VoiceOver announces them.
        if traits.contains(.selected) { spokenParts.append("Selected") }
        if traits.contains(.notEnabled) { spokenParts.append("Dimmed") }

        // The button word is suppressed for keyboard keys (VoiceOver never says it
        // there). Switch/tab/back suppression relies on private traits we don't read.
        if traits.contains(.button), !traits.contains(.keyboardKey) { spokenParts.append("Button") }
        if traits.contains(.header) { spokenParts.append("Heading") }
        if traits.contains(.link) { spokenParts.append("Link") }
        if traits.contains(.searchField) { spokenParts.append("Search Field") }
        if traits.contains(.image) { spokenParts.append("Image") }
        if traits.contains(.adjustable) { spokenParts.append("Adjustable") }

        let description = spokenParts.joined(separator: ", ")

        // Hint: the custom hint first, then the trait-injected adjustable hint,
        // matching VoiceOver's "<hint>. Swipe up or down…" ordering.
        var hintParts: [String] = []
        if let hint, !hint.isEmpty { hintParts.append(hint) }
        if traits.contains(.adjustable) {
            hintParts.append("Swipe up or down with one finger to adjust the value.")
        }
        let composedHint = hintParts.isEmpty ? nil : hintParts.joined(separator: " ")

        return VoiceOverUtterance(description: description, hint: composedHint)
    }
}
