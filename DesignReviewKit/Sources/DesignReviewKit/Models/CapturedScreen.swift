//
//  CapturedScreen.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

/// One frozen screenshot of the host app plus the annotations drawn on it.
nonisolated struct CapturedScreen: Identifiable, Sendable {
    let id: UUID

    /// JPEG-compressed capture; decode on demand to keep multi-screen sessions memory-bounded.
    let imageData: Data

    /// Capture size in points; pairs with normalized annotation rects for any target space.
    let imagePointSize: CGSize

    /// Display scale at capture time; restore it on decode so point sizes stay true.
    let displayScale: CGFloat

    let capturedAt: Date

    var annotations: [Annotation]

    /// Frames of the window's views and accessibility elements at capture time,
    /// in unit coordinates. Measurement mode snaps to these edges.
    let elementFrames: [CGRect]

    /// Text elements with their resolved typography at capture time, in unit
    /// coordinates. Typography mode outlines and inspects these.
    let textElements: [CapturedTextElement]

    /// Whether SwiftUI drew text this capture couldn't resolve fonts for —
    /// the reflection-based extraction broke on this OS version.
    let fontExtractionUnavailable: Bool

    /// Accessibility elements with their raw properties at capture time, in unit
    /// coordinates. Accessibility mode outlines and inspects these.
    let accessibilityElements: [CapturedAccessibilityElement]

    /// Whether content was drawn but the accessibility tree was empty — the
    /// runtime wasn't materialized (no assistive tech / host enabler) this capture.
    let accessibilityTreeUnavailable: Bool

    /// Decode the stored capture at its original scale.
    func makeImage() -> UIImage? {
        UIImage(data: imageData, scale: displayScale)
    }

}
