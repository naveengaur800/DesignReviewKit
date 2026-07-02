//
//  InspectorViewModel+RenderModels.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

// Render models: everything the inspector views need to draw, derived from the
// session by `AnnotatingStateBuilder`. Views read these and dispatch events —
// they never touch the session directly.
extension InspectorViewModel {

    /// Everything the annotation canvas and its chrome need to render.
    struct AnnotatingState {
        /// Active screen identity; keys per-screen view state such as measurements.
        let screenID: UUID?
        /// `nil` when the stored capture fails to decode; the canvas shows a placeholder.
        let image: UIImage?
        let imagePointSize: CGSize
        var annotations: [AnnotationDisplayItem]
        /// Rubber-band rect while the designer is still dragging, in normalized coordinates.
        var draftRect: CGRect?
        /// Committed rect awaiting its comment, recolored live as the sheet's severity changes.
        let pendingRect: PendingRectDisplay?
        let thumbnails: [ThumbnailItem]
        /// Element frames in unit coordinates, for measurement-mode edge snapping.
        let elementFrames: [CGRect]
        /// Text elements with resolved typography, for typography-mode inspection.
        let textElements: [CapturedTextElement]
        /// Whether typography mode should explain missing SwiftUI fonts with a banner.
        let fontExtractionUnavailable: Bool
        /// Host mapping from readings to design-token names; `nil` shows raw readings.
        let tokenResolver: (any DesignTokenResolving)?
    }

    struct AnnotationDisplayItem: Identifiable {
        let id: UUID
        var normalizedRect: CGRect
        let severity: Severity
        let number: Int
        let isSelected: Bool
    }

    /// Rect awaiting its comment, rendered beneath the comment sheet.
    struct PendingRectDisplay {
        let normalizedRect: CGRect
        let severity: Severity
    }

    struct ThumbnailItem: Identifiable {
        let id: UUID
        /// `nil` when the stored capture fails to decode; the strip shows a placeholder.
        let image: UIImage?
        let isActive: Bool
    }

    /// Comment sheet contents for a new or existing annotation.
    struct CommentDraft: Identifiable {
        enum Target {
            case newAnnotation(normalizedRect: CGRect)
            case existingAnnotation(id: UUID)
        }

        let id: UUID
        let title: String
        let target: Target
        var text: String
        var severity: Severity
    }

    /// Generated PDF ready for preview and sharing.
    struct ExportedReport: Identifiable {
        let url: URL
        var id: URL { url }
    }
}
