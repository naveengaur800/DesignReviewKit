//
//  TypographyCanvasView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 02/07/2026.
//

import SwiftUI
import UIKit

/// Font-revealing overlay: every captured text element is outlined; tapping one
/// presents a glass card with its resolved fonts and a copy affordance for
/// carrying the identity into an annotation comment. Overlapping elements
/// cycle on repeated taps, smallest first.
///
/// Font readouts are transient tooling — they live only in this view's state
/// and never enter the session, the annotations, or the PDF report.
struct TypographyCanvasView: View {

    let imagePointSize: CGSize
    /// Text elements in unit coordinates with their resolved fonts.
    let textElements: [CapturedTextElement]
    /// Whether extraction recovered nothing despite SwiftUI text being drawn;
    /// shows one explanatory banner instead of N empty cards.
    let isExtractionUnavailable: Bool

    @State
    private var selectedElementID: UUID?

    @State
    private var didCopy = false

    /// Monotonic tap counter keying the confirmation-reset task, so re-copying
    /// while the checkmark shows restarts the timer instead of inheriting it.
    @State
    private var copyCount = 0

    @State
    private var selectionHaptics = UIImpactFeedbackGenerator(style: .light)

    private enum Metrics {
        static let cardLift: CGFloat = 46
        static let cardEdgeInsetX: CGFloat = 90
        static let cardEdgeInsetY: CGFloat = 46
        static let copyConfirmationSeconds: Double = 1.2
    }

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = CGRect.aspectFitRect(
                for: imagePointSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                ForEach(textElements) { element in
                    elementOutline(element, imageFrame: imageFrame)
                }

                if let element = selectedElement {
                    fontCard(for: element, imageFrame: imageFrame)
                }

                if isExtractionUnavailable {
                    unavailableBanner
                        .position(x: imageFrame.midX, y: imageFrame.minY + 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, imageFrame: imageFrame)
            }
        }
        .task(id: copyCount) {
            // Show the copy confirmation briefly, then restore the affordance.
            guard copyCount > 0 else { return }
            try? await Task.sleep(for: .seconds(Metrics.copyConfirmationSeconds))
            didCopy = false
        }
    }

    // MARK: - Selection

    private var selectedElement: CapturedTextElement? {
        textElements.first { $0.id == selectedElementID }
    }

    /// The element's on-canvas rect, clipped to the capture: elements straddling
    /// the capture edge mid-scroll must not draw or hit-test over the chrome.
    /// `.null` when nothing of the element is visible.
    private func displayRect(for element: CapturedTextElement, in imageFrame: CGRect) -> CGRect {
        element.normalizedRect.denormalized(in: imageFrame).intersection(imageFrame)
    }

    /// Select the smallest text element under the tap; repeated taps cycle
    /// through overlapping elements, and tapping clear space dismisses.
    private func handleTap(at location: CGPoint, imageFrame: CGRect) {
        let candidates = textElements
            .map { (element: $0, rect: displayRect(for: $0, in: imageFrame)) }
            .filter { !$0.rect.isNull && $0.rect.contains(location) }
            .sorted { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            didCopy = false
            guard !candidates.isEmpty else {
                selectedElementID = nil
                return
            }
            if let currentIndex = candidates.firstIndex(where: { $0.element.id == selectedElementID }) {
                if candidates.count == 1 {
                    selectedElementID = nil
                } else {
                    selectedElementID = candidates[(currentIndex + 1) % candidates.count].element.id
                    selectionHaptics.impactOccurred()
                }
            } else {
                selectedElementID = candidates[0].element.id
                selectionHaptics.impactOccurred()
            }
        }
    }

    // MARK: - Outlines

    @ViewBuilder
    private func elementOutline(_ element: CapturedTextElement, imageFrame: CGRect) -> some View {
        let rect = displayRect(for: element, in: imageFrame)
        if !rect.isNull, rect.width > 0.5, rect.height > 0.5 {
            let isSelected = element.id == selectedElementID
            ZStack {
                if isSelected {
                    Path { $0.addRect(rect) }
                        .fill(Color.indigo.opacity(0.08))
                }
                Path { $0.addRect(rect) }
                    .stroke(Color.indigo.opacity(isSelected ? 1 : 0.55), lineWidth: isSelected ? 1.5 : 1)
            }
        }
    }

    // MARK: - Font Card

    private func fontCard(for element: CapturedTextElement, imageFrame: CGRect) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if element.fonts.isEmpty {
                    Text("Font unavailable")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(element.fonts, id: \.self) { font in
                        HStack(spacing: 6) {
                            if let color = font.color {
                                colorSwatch(color)
                            }
                            Text(font.summary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                // Long identities (custom faces + hex) scale down
                                // rather than wrap and misalign the swatch.
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }

                Text("“\(element.string)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !element.fonts.isEmpty {
                copyButton(for: element)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        // Swallow taps on the card body: a copy tap that misses the button must
        // not fall through and reselect whatever sits under the card.
        .onTapGesture {}
        .frame(maxWidth: 300)
        .position(cardPosition(for: element, in: imageFrame))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func copyButton(for element: CapturedTextElement) -> some View {
        Button {
            UIPasteboard.general.string = copySummary(for: element)
            selectionHaptics.impactOccurred()
            didCopy = true
            copyCount += 1
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(didCopy ? Color.green : Color.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy Font Summary")
    }

    /// Rendered ink of a run; the ring keeps near-white swatches visible on glass.
    private func colorSwatch(_ color: TextColor) -> some View {
        Circle()
            .fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
    }

    /// One-line handoff for annotation comments, e.g.
    /// `GTAmerica-Bold · 19pt · #1C1C1E — "Profile Header"`.
    private func copySummary(for element: CapturedTextElement) -> String {
        let fonts = element.fonts.map(\.summary).joined(separator: " | ")
        return "\(fonts) — “\(element.string.prefix(60))”"
    }

    /// Float the card just above the element's visible portion, clamped inside
    /// the capture.
    private func cardPosition(for element: CapturedTextElement, in imageFrame: CGRect) -> CGPoint {
        let rect = displayRect(for: element, in: imageFrame)
        guard !rect.isNull else { return CGPoint(x: imageFrame.midX, y: imageFrame.midY) }
        return CGPoint(x: rect.midX, y: rect.minY - Metrics.cardLift)
            .clamped(to: imageFrame.insetBy(dx: Metrics.cardEdgeInsetX, dy: Metrics.cardEdgeInsetY))
    }

    // MARK: - Extraction Banner

    private var unavailableBanner: some View {
        Label(
            "Font extraction isn't available on this iOS version",
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}
