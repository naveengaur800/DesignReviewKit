//
//  InspectorRootView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI

/// Screenshot-editor layout: the frozen capture sits as a rounded card on a neutral
/// backdrop with the controls in clear space, so every pixel of the capture —
/// including the host's nav bar — is annotatable.
///
/// Entry mirrors Apple's screenshot affordance: the capture appears full-bleed,
/// pixel-aligned with the live UI (the screen "freezes"), then springs down into
/// the card while backdrop and chrome fade in.
struct InspectorRootView: View {

    @ObservedObject
    private var viewModel: InspectorViewModel

    @State
    private var isEndSessionConfirmationPresented = false

    @State
    private var hasEntered = false

    init(viewModel: InspectorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        switch viewModel.viewState {
        case .annotating(let state):
            annotatingBody(state)
        }
    }

    private func annotatingBody(_ state: InspectorViewModel.AnnotatingState) -> some View {
        ZStack {
            Color(.secondarySystemBackground)
                .ignoresSafeArea()
                .opacity(hasEntered ? 1 : 0)

            VStack(spacing: 0) {
                chromeBar
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .opacity(hasEntered ? 1 : 0)

                GeometryReader { cardProxy in
                    ZStack {
                        AnnotationCanvasView(state: state) { event in
                            viewModel.dispatch(with: .canvas(event))
                        }
                        .allowsHitTesting(viewModel.activeTool == nil)

                        // Tool overlays get fresh state per screen — a readout on
                        // one capture means nothing over another.
                        switch viewModel.activeTool {
                        case .measure:
                            MeasurementCanvasView(
                                imagePointSize: state.imagePointSize,
                                elementFrames: state.elementFrames
                            )
                            .id(state.screenID)

                        case .typography:
                            TypographyCanvasView(
                                imagePointSize: state.imagePointSize,
                                textElements: state.textElements,
                                isExtractionUnavailable: state.fontExtractionUnavailable
                            )
                            .id(state.screenID)

                        case nil:
                            EmptyView()
                        }
                    }
                    .scaleEffect(hasEntered ? 1 : entryScale(for: state, in: cardProxy))
                    .offset(y: hasEntered ? 0 : entryOffsetY(for: state, in: cardProxy))
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, state.thumbnails.isEmpty ? 24 : 10)

                if !state.thumbnails.isEmpty {
                    ThumbnailStripView(thumbnails: state.thumbnails) { screenID in
                        viewModel.dispatch(with: .toolbar(.thumbnailTapped(screenID: screenID)))
                    }
                    .padding(.bottom, 8)
                    .opacity(hasEntered ? 1 : 0)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                hasEntered = true
            }
        }
        .sheet(item: commentDraftBinding) { draft in
            CommentSheetView(
                draft: draft,
                onSeverityChange: { viewModel.dispatch(with: .commentSheet(.severityChanged($0))) },
                onSave: { text, severity in
                    viewModel.dispatch(with: .commentSheet(.saveTapped(text: text, severity: severity)))
                },
                onCancel: { viewModel.dispatch(with: .commentSheet(.dismissed)) }
            )
        }
        .sheet(item: exportedReportBinding) { report in
            ReportPreviewView(url: report.url) {
                viewModel.dispatch(with: .export(.previewDismissed))
            }
        }
        .alert(
            "Export Failed",
            isPresented: exportErrorBinding
        ) {
            Button("OK", role: .cancel) {
                viewModel.dispatch(with: .export(.errorDismissed))
            }
        } message: {
            Text(viewModel.exportErrorMessage ?? "")
        }
        .overlay {
            if viewModel.isGeneratingReport {
                generatingOverlay
            }
        }
        .alert(
            "End session?",
            isPresented: $isEndSessionConfirmationPresented
        ) {
            Button("End Session", role: .destructive) {
                viewModel.dispatch(with: .toolbar(.endSessionConfirmed))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All screens and annotations will be discarded. This can't be undone.")
        }
    }

    // MARK: - Entry Transition

    /// Scale that makes the inset card exactly cover the window, so the capture
    /// starts pixel-aligned with the live UI before springing into place.
    /// The capture's point size is the window's size — no extra geometry needed.
    private func entryScale(for state: InspectorViewModel.AnnotatingState, in proxy: GeometryProxy) -> CGFloat {
        let fitted = CGRect.aspectFitRect(for: state.imagePointSize, in: proxy.frame(in: .global))
        guard fitted.height > 0 else { return 1 }
        return state.imagePointSize.height / fitted.height
    }

    /// Vertical shift aligning the card's center with the window's center at entry.
    private func entryOffsetY(for state: InspectorViewModel.AnnotatingState, in proxy: GeometryProxy) -> CGFloat {
        let fitted = CGRect.aspectFitRect(for: state.imagePointSize, in: proxy.frame(in: .global))
        return state.imagePointSize.height / 2 - fitted.midY
    }

    // MARK: - Chrome

    /// ✕ and ⏹ leading; export and ✓ trailing, in clear space beside the card.
    /// Annotations save as they're made, so ✓ simply confirms and closes —
    /// there is no explicit save.
    private var chromeBar: some View {
        GlassEffectContainer(spacing: 10) {
            chromeBarContent
        }
    }

    private var chromeBarContent: some View {
        HStack {
            HStack(spacing: 10) {
                Button {
                    viewModel.dispatch(with: .toolbar(.closeTapped))
                } label: {
                    chromeIcon("xmark")
                }
                .accessibilityLabel("Close Inspector")

                Button {
                    isEndSessionConfirmationPresented = true
                } label: {
                    chromeIcon("rectangle.portrait.and.arrow.right", isDestructive: true)
                }
                .accessibilityLabel("End Session")
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    viewModel.dispatch(with: .toolbar(.toolToggled(.measure)))
                } label: {
                    chromeIcon("ruler", isProminent: viewModel.activeTool == .measure)
                }
                .accessibilityLabel("Measure Distances")

                Button {
                    viewModel.dispatch(with: .toolbar(.toolToggled(.typography)))
                } label: {
                    chromeIcon("textformat", isProminent: viewModel.activeTool == .typography)
                }
                .accessibilityLabel("Inspect Fonts")

                Button {
                    viewModel.dispatch(with: .toolbar(.exportTapped))
                } label: {
                    chromeIcon("doc.text", isEnabled: viewModel.canGenerateReport)
                }
                .disabled(!viewModel.canGenerateReport)
                .accessibilityLabel("Generate PDF Report")

                Button {
                    viewModel.dispatch(with: .toolbar(.closeTapped))
                } label: {
                    chromeIcon("checkmark", isProminent: true)
                }
                .accessibilityLabel("Done Annotating")
            }
        }
    }

    private static let chromeControlSize: CGFloat = 38

    /// Circular Liquid Glass control; the prominent variant tints with the accent
    /// color, and the destructive variant carries a red glyph.
    private func chromeIcon(
        _ systemName: String,
        isProminent: Bool = false,
        isEnabled: Bool = true,
        isDestructive: Bool = false
    ) -> some View {
        let foreground: AnyShapeStyle = isProminent && isEnabled
            ? AnyShapeStyle(.white)
            : isDestructive
                ? AnyShapeStyle(Color.red)
                : AnyShapeStyle(isEnabled ? Color.secondary : Color(.tertiaryLabel))

        return Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: Self.chromeControlSize, height: Self.chromeControlSize)
            .glassEffect(chromeGlass(isProminent: isProminent, isEnabled: isEnabled), in: .circle)
    }

    /// Tint the prominent control's glass; shimmer on touch only while enabled.
    private func chromeGlass(isProminent: Bool, isEnabled: Bool) -> Glass {
        guard isEnabled else { return .regular }
        return isProminent ? .regular.tint(.accentColor).interactive() : .regular.interactive()
    }

    // MARK: - Bindings

    /// Bridge the ViewModel's encapsulated presentation state into sheet bindings:
    /// the setter only forwards dismissal as an event, never mutates state directly.
    private var commentDraftBinding: Binding<InspectorViewModel.CommentDraft?> {
        Binding(
            get: { viewModel.commentDraft },
            set: { newValue in
                if newValue == nil {
                    viewModel.dispatch(with: .commentSheet(.dismissed))
                }
            }
        )
    }

    private var exportedReportBinding: Binding<InspectorViewModel.ExportedReport?> {
        Binding(
            get: { viewModel.exportedReport },
            set: { newValue in
                if newValue == nil {
                    viewModel.dispatch(with: .export(.previewDismissed))
                }
            }
        )
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.exportErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dispatch(with: .export(.errorDismissed))
                }
            }
        )
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            ProgressView("Generating report…")
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }
}

