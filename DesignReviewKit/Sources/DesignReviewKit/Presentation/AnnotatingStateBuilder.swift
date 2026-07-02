//
//  AnnotatingStateBuilder.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

/// Derive the inspector's render models from a session — pure presentation
/// mapping with no business rules and no mutation beyond the shared image cache.
enum AnnotatingStateBuilder {

    /// Build the canvas render model for the active screen.
    static func makeState(
        session: ReviewSession,
        activeScreenID: UUID?,
        selectedAnnotationID: UUID?,
        draftRect: CGRect?,
        commentDraft: InspectorViewModel.CommentDraft?,
        imageCache: ScreenImageCache,
        tokenResolver: (any DesignTokenResolving)?
    ) -> InspectorViewModel.AnnotatingState {
        let screen = session.screens.first { $0.id == activeScreenID } ?? session.screens.last

        var pendingRect: InspectorViewModel.PendingRectDisplay?
        if let draft = commentDraft, case .newAnnotation(let rect) = draft.target {
            pendingRect = InspectorViewModel.PendingRectDisplay(
                normalizedRect: rect,
                severity: draft.severity
            )
        }

        // Number every annotation in one pass; per-annotation lookups would be O(n²).
        let activeScreenIssues = session.numberedIssues.filter { $0.screenID == screen?.id }

        return InspectorViewModel.AnnotatingState(
            screenID: screen?.id,
            image: screen.flatMap { imageCache.image(for: $0) },
            imagePointSize: screen?.imagePointSize ?? .zero,
            annotations: activeScreenIssues.map { issue in
                InspectorViewModel.AnnotationDisplayItem(
                    id: issue.annotation.id,
                    normalizedRect: issue.annotation.normalizedRect,
                    severity: issue.annotation.severity,
                    number: issue.number,
                    isSelected: issue.annotation.id == selectedAnnotationID
                )
            },
            draftRect: draftRect,
            pendingRect: pendingRect,
            thumbnails: session.screens.count > 1
                ? session.screens.map { thumbnailScreen in
                    InspectorViewModel.ThumbnailItem(
                        id: thumbnailScreen.id,
                        image: imageCache.image(for: thumbnailScreen),
                        isActive: thumbnailScreen.id == screen?.id
                    )
                }
                : [],
            elementFrames: screen?.elementFrames ?? [],
            textElements: screen?.textElements ?? [],
            fontExtractionUnavailable: screen?.fontExtractionUnavailable ?? false,
            accessibilityElements: screen?.accessibilityElements ?? [],
            accessibilityTreeUnavailable: screen?.accessibilityTreeUnavailable ?? false,
            tokenResolver: tokenResolver
        )
    }

}
