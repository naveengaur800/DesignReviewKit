//
//  AccessibilityCanvasView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 03/07/2026.
//

import SwiftUI
import UIKit

/// Accessibility-revealing overlay: every captured element is outlined — the set
/// VoiceOver can reach, in its flick order — and tapping one presents a glass
/// card of the raw properties a developer set (label, value, hint, traits,
/// identifier). Elements missing a label are flagged. Overlapping elements cycle
/// on repeated taps, smallest first.
///
/// Readouts are transient tooling — they live only in this view's state and never
/// enter the session, the annotations, or the PDF report.
struct AccessibilityCanvasView: View {

    let imagePointSize: CGSize
    /// Accessibility elements in unit coordinates with their raw properties.
    let elements: [CapturedAccessibilityElement]
    /// Whether the tree was empty while content was drawn — shows one banner
    /// explaining the runtime wasn't materialized, instead of nothing at all.
    let isTreeUnavailable: Bool

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

    /// Measured card size, so positioning clamps with real extents.
    @State
    private var cardSize: CGSize = .zero

    /// Speaks the selected element's VoiceOver utterance aloud.
    @State
    private var speech = AccessibilitySpeechController()

    private enum Metrics {
        static let cardSpacing: CGFloat = 12
        static let cardEdgeMargin: CGFloat = 8
        static let cardMaxWidth: CGFloat = 300
        /// Worst-case footprint used for the first frame, before measurement.
        static let estimatedCardSize = CGSize(width: 300, height: 150)
        static let copyConfirmationSeconds: Double = 1.2
    }

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = CGRect.aspectFitRect(
                for: imagePointSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                ForEach(elements) { element in
                    elementOutline(element, imageFrame: imageFrame)
                }

                if let element = selectedElement {
                    propertyCard(for: element, imageFrame: imageFrame)
                }

                if isTreeUnavailable {
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
            guard copyCount > 0 else { return }
            try? await Task.sleep(for: .seconds(Metrics.copyConfirmationSeconds))
            didCopy = false
        }
        // Release the audio session when leaving the mode (tool switch, screen
        // change via `.id`, or dismiss), restoring other apps' audio.
        .onDisappear { speech.end() }
    }

    // MARK: - Selection

    private var selectedElement: CapturedAccessibilityElement? {
        elements.first { $0.id == selectedElementID }
    }

    /// The element's on-canvas rect, clipped to the capture so elements straddling
    /// the edge mid-scroll don't draw or hit-test over the chrome. `.null` when
    /// nothing is visible.
    private func displayRect(for element: CapturedAccessibilityElement, in imageFrame: CGRect) -> CGRect {
        element.normalizedRect.denormalized(in: imageFrame).intersection(imageFrame)
    }

    /// Select the smallest element under the tap; repeated taps cycle overlapping
    /// elements, and tapping clear space dismisses.
    private func handleTap(at location: CGPoint, imageFrame: CGRect) {
        let candidates = elements
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

        // Speak the newly selected element, or fall silent when clearing.
        if let element = selectedElement {
            speech.speak(element.voiceOver)
        } else {
            speech.stop()
        }
    }

    // MARK: - Outlines

    @ViewBuilder
    private func elementOutline(_ element: CapturedAccessibilityElement, imageFrame: CGRect) -> some View {
        let rect = displayRect(for: element, in: imageFrame)
        if !rect.isNull, rect.width > 0.5, rect.height > 0.5 {
            let isSelected = element.id == selectedElementID
            let isFlagged = !element.flags.isEmpty
            let color: Color = isFlagged ? .orange : .accentColor
            ZStack {
                if isSelected {
                    Path { $0.addRect(rect) }
                        .fill(color.opacity(0.12))
                }
                Path { $0.addRect(rect) }
                    .stroke(color.opacity(isSelected ? 1 : 0.55), lineWidth: isSelected ? 1.5 : 1)
            }
        }
    }

    // MARK: - Property Card

    private func propertyCard(for element: CapturedAccessibilityElement, imageFrame: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                labelRow(for: element)
                Spacer(minLength: 8)
                if !element.voiceOver.isEmpty {
                    speakerButton(for: element)
                }
                copyButton(for: element)
            }

            spokenLine(for: element)

            propertyRow("Value", element.value)
            propertyRow("Hint", element.hint)
            propertyRow("Traits", element.traitNames.isEmpty ? nil : element.traitNames.joined(separator: ", "))
            propertyRow("ID", element.identifier)

            if element.flags.contains(.missingLabel) {
                flagCallout("Missing accessibility label")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: Metrics.cardMaxWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        // Swallow taps on the card body so a mis-tap doesn't reselect underneath.
        .onTapGesture {}
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            cardSize = size
        }
        .position(cardPosition(for: element, in: imageFrame))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// Label leads the card; a missing label reads as an explicit finding.
    @ViewBuilder
    private func labelRow(for element: CapturedAccessibilityElement) -> some View {
        if element.hasLabel {
            Text(element.label ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        } else {
            Label("No label", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func propertyRow(_ key: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(key)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func flagCallout(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.top, 2)
    }

    /// The composed announcement VoiceOver would speak, shown so it can be read
    /// as well as heard.
    @ViewBuilder
    private func spokenLine(for element: CapturedAccessibilityElement) -> some View {
        if !element.voiceOver.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption2)
                Text(element.voiceOver.spoken)
                    .font(.caption)
                    .italic()
                    .lineLimit(2)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
        }
    }

    private func speakerButton(for element: CapturedAccessibilityElement) -> some View {
        Button {
            speech.speak(element.voiceOver)
            selectionHaptics.impactOccurred()
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play VoiceOver Announcement")
    }

    private func copyButton(for element: CapturedAccessibilityElement) -> some View {
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
        .accessibilityLabel("Copy Accessibility Summary")
    }

    /// One-line handoff for an annotation comment, e.g.
    /// `"Follow" · Button · #profile_follow_button`.
    private func copySummary(for element: CapturedAccessibilityElement) -> String {
        var parts = [element.hasLabel ? "“\(element.label ?? "")”" : "(no label)"]
        if !element.traitNames.isEmpty {
            parts.append(element.traitNames.joined(separator: ", "))
        }
        if let identifier = element.identifier {
            parts.append("#\(identifier)")
        }
        return parts.joined(separator: " · ")
    }

    /// Float the card above the element's visible portion, clamped inside the
    /// capture using its measured size and flipping below when there's no room —
    /// the card never crops at an edge and never covers the element it describes.
    private func cardPosition(for element: CapturedAccessibilityElement, in imageFrame: CGRect) -> CGPoint {
        let rect = displayRect(for: element, in: imageFrame)
        guard !rect.isNull else { return CGPoint(x: imageFrame.midX, y: imageFrame.midY) }

        let size = cardSize == .zero ? Metrics.estimatedCardSize : cardSize
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let minX = imageFrame.minX + halfWidth + Metrics.cardEdgeMargin
        let maxX = imageFrame.maxX - halfWidth - Metrics.cardEdgeMargin
        let x = minX <= maxX ? min(max(rect.midX, minX), maxX) : imageFrame.midX

        let topEdgeIfAbove = rect.minY - Metrics.cardSpacing - size.height
        let y = topEdgeIfAbove >= imageFrame.minY + Metrics.cardEdgeMargin
            ? rect.minY - Metrics.cardSpacing - halfHeight
            : min(rect.maxY + Metrics.cardSpacing + halfHeight,
                  imageFrame.maxY - halfHeight - Metrics.cardEdgeMargin)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Unavailable Banner

    private var unavailableBanner: some View {
        Label(
            "Accessibility tree unavailable — enable the runtime to inspect",
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}
