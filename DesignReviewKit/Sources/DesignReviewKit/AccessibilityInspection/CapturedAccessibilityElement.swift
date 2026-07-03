//
//  CapturedAccessibilityElement.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 03/07/2026.
//

import UIKit

/// One accessibility element captured with the screen, for accessibility mode.
///
/// Carries the raw `UIAccessibility` properties a developer set — the same
/// inputs VoiceOver reads — plus factual review flags. Composing what VoiceOver
/// *speaks* is deliberately out of scope; this reports the truth on the element.
nonisolated struct CapturedAccessibilityElement: Identifiable, Sendable, Equatable {
    let id: UUID

    /// Frame in unit coordinates relative to the capture.
    let normalizedRect: CGRect

    let label: String?
    let value: String?
    let hint: String?

    /// `accessibilityIdentifier` — a developer/testing hook, never spoken.
    let identifier: String?

    /// VoiceOver-facing trait names in table order, e.g. `["Button", "Selected"]`.
    let traitNames: [String]

    /// The source object's class, e.g. `AccessibilityNode` (SwiftUI) or `UIButton`.
    let sourceClass: String

    /// What VoiceOver would speak for this element, composed at capture time.
    let voiceOver: VoiceOverUtterance

    /// Factual review findings computed at capture.
    let flags: Set<Flag>

    /// A factual accessibility defect — no heuristics, no guessing intent.
    enum Flag: Sendable {
        /// An interactive or image element with no accessibility label; VoiceOver
        /// would land on it and announce no name.
        case missingLabel
    }

    var hasLabel: Bool {
        !(label ?? "").isEmpty
    }
}

/// Map the public `UIAccessibilityTraits` bits to VoiceOver-facing names, and
/// decide which traits imply an element should carry a label.
nonisolated enum AccessibilityTraitDecoder {

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

    /// Interactive or image traits — an element carrying one is expected to have
    /// a label, so a missing one is a factual defect.
    private static let labelExpectingTraits: UIAccessibilityTraits =
        [.button, .link, .adjustable, .image, .searchField, .keyboardKey, .tabBar]

    /// Readable trait names contained in `traits`, in table order.
    static func names(for traits: UIAccessibilityTraits) -> [String] {
        table.filter { traits.contains($0.0) }.map(\.1)
    }

    /// Whether an element with these traits ought to carry a label.
    static func expectsLabel(_ traits: UIAccessibilityTraits) -> Bool {
        !traits.intersection(labelExpectingTraits).isEmpty
    }
}
