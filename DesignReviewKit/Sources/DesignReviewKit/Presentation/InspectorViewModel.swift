//
//  InspectorViewModel.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import OSLog
import SwiftUI
import UIKit

/// Drive the inspector UI: annotation canvas, comment sheet, session review, and export.
///
/// One instance lives for the whole session (owned by `DesignInspector`) so annotated
/// screens survive while the inspector is suspended between captures. Domain mutations
/// live on `ReviewSession`; render-model derivation lives in `AnnotatingStateBuilder` —
/// this type coordinates events, selection, and presentation state.
final class InspectorViewModel: ObservableObject {

    // MARK: - ViewState

    enum ViewState {
        case annotating(AnnotatingState)
    }

    // MARK: - Tools

    /// Transient canvas overlay tools, mutually exclusive with each other and
    /// with annotating. Their readouts never enter the session or the report.
    enum InspectorTool {
        case measure
        case typography
    }

    // MARK: - ViewEvent

    enum ViewEvent {
        case canvas(CanvasEvent)
        case toolbar(ToolbarEvent)
        case commentSheet(CommentSheetEvent)
        case export(ExportEvent)

        enum CanvasEvent {
            case drawingUpdated(normalizedRect: CGRect)
            case drawingEnded
            case annotationTapped(id: UUID)
            case emptyAreaTapped
            case selectedAnnotationFrameChanged(normalizedRect: CGRect)
            case editCommentTapped
            case deleteSelectedTapped
        }

        enum ToolbarEvent {
            case closeTapped
            case exportTapped
            case toolToggled(InspectorTool)
            case endSessionConfirmed
            case thumbnailTapped(screenID: UUID)
        }

        enum CommentSheetEvent {
            case severityChanged(Severity)
            case saveTapped(text: String, severity: Severity)
            case dismissed
        }

        enum ExportEvent {
            case previewDismissed
            case errorDismissed
        }
    }

    // MARK: - Published State

    @Published
    private(set) var viewState: ViewState

    /// Comment sheet contents; `nil` while the sheet is hidden.
    @Published
    private(set) var commentDraft: CommentDraft?

    /// Active overlay tool on the canvas; `nil` while annotating.
    @Published
    private(set) var activeTool: InspectorTool?

    @Published
    private(set) var isGeneratingReport = false

    /// Generated PDF awaiting preview; `nil` once the preview is dismissed.
    @Published
    private(set) var exportedReport: ExportedReport?

    /// Export failure message for the error alert; `nil` while no error is shown.
    @Published
    private(set) var exportErrorMessage: String?

    // MARK: - Private State

    private var session: ReviewSession
    private var activeScreenID: UUID?
    private var selectedAnnotationID: UUID?
    private var draftNormalizedRect: CGRect?

    private let imageCache = ScreenImageCache()
    private let reportGenerator: PDFReportGenerator
    private let onSuspend: () -> Void
    private let onEndSession: () -> Void
    private let logger = Logger(subsystem: "DesignReviewKit", category: "Inspector")

    /// Discard committed rects smaller than this in screenshot points (filters accidental micro-drags).
    private static let minimumAnnotationSide: CGFloat = 16

    // MARK: - Init

    init(
        session: ReviewSession,
        reportGenerator: PDFReportGenerator = PDFReportGenerator(),
        onSuspend: @escaping () -> Void,
        onEndSession: @escaping () -> Void
    ) {
        self.session = session
        self.reportGenerator = reportGenerator
        self.onSuspend = onSuspend
        self.onEndSession = onEndSession
        self.activeScreenID = session.screens.last?.id
        self.viewState = .annotating(AnnotatingStateBuilder.makeState(
            session: session,
            activeScreenID: session.screens.last?.id,
            selectedAnnotationID: nil,
            draftRect: nil,
            commentDraft: nil,
            imageCache: imageCache
        ))
    }

    // MARK: - Session Entry Points (DesignInspector)

    /// Append a fresh capture when the host trigger re-enters annotate mode.
    /// Each entry is a new screen; the session accumulates them until ended.
    func appendCapturedScreen(_ screen: CapturedScreen) {
        session.screens.append(screen)
        activeScreenID = screen.id
        selectedAnnotationID = nil
        draftNormalizedRect = nil
        activeTool = nil
        syncViewState()
    }

    // MARK: - Derived Flags

    var hasIssues: Bool {
        session.issueCount > 0
    }

    /// Whether an export can start — there must be something to report and no export in flight.
    var canGenerateReport: Bool {
        hasIssues && !isGeneratingReport
    }

    // MARK: - Dispatch

    func dispatch(with event: ViewEvent) {
        switch event {
        case .canvas(let action):
            handleCanvasEvent(action)
        case .toolbar(let action):
            handleToolbarEvent(action)
        case .commentSheet(let action):
            handleCommentSheetEvent(action)
        case .export(let action):
            handleExportEvent(action)
        }
    }

    // MARK: - Canvas Handlers

    private func handleCanvasEvent(_ action: ViewEvent.CanvasEvent) {
        switch action {
        case .drawingUpdated(let normalizedRect):
            draftNormalizedRect = normalizedRect
            // Hot path (every drag frame): touch only the draft rect rather than
            // re-deriving the full state, which sorts and renumbers all annotations.
            mutateAnnotatingState { $0.draftRect = normalizedRect }

        case .drawingEnded:
            commitDraftRect()

        case .annotationTapped(let id):
            selectedAnnotationID = id
            syncViewState()

        case .emptyAreaTapped:
            selectedAnnotationID = nil
            syncViewState()

        case .selectedAnnotationFrameChanged(let normalizedRect):
            moveSelectedAnnotation(to: normalizedRect)

        case .editCommentTapped:
            presentCommentSheetForSelection()

        case .deleteSelectedTapped:
            deleteSelectedAnnotation()
        }
    }

    /// Hot path (every move/resize drag frame): write the session's source of
    /// truth, then patch just the selected display item instead of re-deriving.
    private func moveSelectedAnnotation(to normalizedRect: CGRect) {
        guard let id = selectedAnnotationID else { return }
        session.updateAnnotation(id: id) { $0.normalizedRect = normalizedRect }
        mutateAnnotatingState { state in
            guard let index = state.annotations.firstIndex(where: \.isSelected) else { return }
            state.annotations[index].normalizedRect = normalizedRect
        }
    }

    private func commitDraftRect() {
        guard let rect = draftNormalizedRect else { return }
        draftNormalizedRect = nil

        guard let screen = activeScreen else {
            syncViewState()
            return
        }

        let rectInScreenPoints = rect.denormalized(in: CGRect(origin: .zero, size: screen.imagePointSize))
        let meetsMinimumSize = rectInScreenPoints.width >= Self.minimumAnnotationSide
            && rectInScreenPoints.height >= Self.minimumAnnotationSide

        if meetsMinimumSize {
            commentDraft = CommentDraft(
                id: UUID(),
                title: "Issue #\(session.issueCount + 1)",
                target: .newAnnotation(normalizedRect: rect),
                text: "",
                severity: .low
            )
        }
        syncViewState()
    }

    private func presentCommentSheetForSelection() {
        guard let id = selectedAnnotationID,
              let annotation = session.annotation(id: id),
              let number = session.issueNumber(for: id) else { return }
        commentDraft = CommentDraft(
            id: UUID(),
            title: "Issue #\(number)",
            target: .existingAnnotation(id: id),
            text: annotation.comment,
            severity: annotation.severity
        )
    }

    private func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        session.removeAnnotation(id: id)
        selectedAnnotationID = nil
        syncViewState()
    }

    // MARK: - Toolbar Handlers

    private func handleToolbarEvent(_ action: ViewEvent.ToolbarEvent) {
        switch action {
        case .closeTapped:
            closeInspector()

        case .exportTapped:
            generateReport()

        case .toolToggled(let tool):
            activeTool = activeTool == tool ? nil : tool

        case .endSessionConfirmed:
            onEndSession()

        case .thumbnailTapped(let screenID):
            activeScreenID = screenID
            selectedAnnotationID = nil
            syncViewState()
        }
    }

    private func closeInspector() {
        selectedAnnotationID = nil
        activeTool = nil
        imageCache.removeImages(forScreenIDs: session.removeEmptyScreens())

        guard !session.screens.isEmpty else {
            // Nothing was annotated anywhere — drop the whole session so the
            // next trigger starts fresh instead of resuming an empty one.
            onEndSession()
            return
        }
        if session.screens.first(where: { $0.id == activeScreenID }) == nil {
            activeScreenID = session.screens.last?.id
        }
        syncViewState()
        onSuspend()
    }

    // MARK: - Comment Sheet Handlers

    private func handleCommentSheetEvent(_ action: ViewEvent.CommentSheetEvent) {
        switch action {
        case .severityChanged(let severity):
            commentDraft?.severity = severity
            syncViewState()

        case .saveTapped(let text, let severity):
            saveComment(text: text, severity: severity)

        case .dismissed:
            // Cancelling a new annotation removes its rect entirely — the invariant
            // that every annotation has a comment is enforced here.
            commentDraft = nil
            syncViewState()
        }
    }

    private func saveComment(text: String, severity: Severity) {
        guard let draft = commentDraft else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch draft.target {
        case .newAnnotation(let normalizedRect):
            guard let screenID = activeScreenID else { break }
            let annotation = Annotation(
                id: UUID(),
                normalizedRect: normalizedRect,
                severity: severity,
                comment: trimmed,
                createdAt: Date()
            )
            session.addAnnotation(annotation, toScreenID: screenID)
            selectedAnnotationID = annotation.id

        case .existingAnnotation(let id):
            selectedAnnotationID = id
            session.updateAnnotation(id: id) {
                $0.comment = trimmed
                $0.severity = severity
            }
        }

        commentDraft = nil
        syncViewState()
    }

    // MARK: - Export Handlers

    private func handleExportEvent(_ action: ViewEvent.ExportEvent) {
        switch action {
        case .previewDismissed:
            exportedReport = nil

        case .errorDismissed:
            exportErrorMessage = nil
        }
    }

    private func generateReport() {
        guard canGenerateReport else { return }
        isGeneratingReport = true

        let sessionSnapshot = session
        let generator = reportGenerator
        Task { [weak self] in
            do {
                let url = try await generator.generateReport(for: sessionSnapshot)
                self?.exportedReport = ExportedReport(url: url)
            } catch {
                self?.logger.error("Report generation failed: \(error)")
                self?.exportErrorMessage = "Couldn't generate the report. Please try again."
            }
            self?.isGeneratingReport = false
        }
    }

    // MARK: - State Derivation

    private var activeScreen: CapturedScreen? {
        session.screens.first { $0.id == activeScreenID }
    }

    private func syncViewState() {
        viewState = .annotating(AnnotatingStateBuilder.makeState(
            session: session,
            activeScreenID: activeScreenID,
            selectedAnnotationID: selectedAnnotationID,
            draftRect: draftNormalizedRect,
            commentDraft: commentDraft,
            imageCache: imageCache
        ))
    }

    /// Patch the current render model in place — for hot paths (drag frames) where
    /// a full `syncViewState()` re-derivation would be wasted work per frame.
    private func mutateAnnotatingState(_ mutate: (inout AnnotatingState) -> Void) {
        guard case .annotating(var state) = viewState else { return }
        mutate(&state)
        viewState = .annotating(state)
    }
}
