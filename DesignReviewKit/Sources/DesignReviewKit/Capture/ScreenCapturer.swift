//
//  ScreenCapturer.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import UIKit

/// Capture a frozen screenshot of a host window before the inspector presents itself.
struct ScreenCapturer {

    /// JPEG quality balancing fidelity against multi-screen session memory.
    private static let compressionQuality: CGFloat = 0.8

    /// Snapshot the window's current contents into a captured screen.
    ///
    /// Capture happens before the inspector's overlay window becomes visible,
    /// so the inspector never appears in its own screenshots.
    ///
    /// - Returns: The captured screen, or `nil` when the window has no size
    ///   or the snapshot can't be encoded.
    func capture(window: UIWindow) -> CapturedScreen? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = window.traitCollection.displayScale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        guard let data = image.jpegData(compressionQuality: Self.compressionQuality) else { return nil }

        let textCapture = TextElementCapturer().capture(in: window)
        return CapturedScreen(
            id: UUID(),
            imageData: data,
            imagePointSize: bounds.size,
            displayScale: format.scale,
            capturedAt: Date(),
            annotations: [],
            elementFrames: normalizedElementFrames(in: window),
            textElements: textCapture.elements,
            fontExtractionUnavailable: textCapture.fontExtractionUnavailable
        )
    }

    // MARK: - Element Frames

    /// Bound the hierarchy walk: plenty for any real screen, cheap to snap against.
    private static let maximumElementCount = 600
    private static let minimumElementSide: CGFloat = 4
    /// Admit hairlines (dividers, separators) despite their sub-point thickness —
    /// they're edges designers measure to — as long as they're long enough to be real rules.
    private static let minimumHairlineThickness: CGFloat = 0.3
    private static let minimumHairlineLength: CGFloat = 12
    private static let maximumWalkDepth = 50

    /// Collect the frames of visibly rendered elements, in unit coordinates,
    /// so measurement mode can snap to and measure between real edges.
    ///
    /// Three sources, deduplicated:
    /// - UIViews that draw something themselves (labels, images, controls,
    ///   filled backgrounds) — clear layout containers would produce lines
    ///   that point at nothing.
    /// - Accessibility elements, via both the array property and the older
    ///   count/at container protocol.
    /// - Layers carrying contents — SwiftUI hosts render text, images, and
    ///   fills through layers rather than subviews, and the accessibility
    ///   tree is empty unless an assistive technology is attached.
    private func normalizedElementFrames(in window: UIWindow) -> [CGRect] {
        let windowBounds = window.bounds
        var frames: [CGRect] = []
        var seenFrameKeys = Set<String>()

        func appendIfMeaningful(_ frame: CGRect) {
            guard frames.count < Self.maximumElementCount,
                  frame.intersects(windowBounds),
                  frame != windowBounds else { return }

            let isRegularElement = frame.width >= Self.minimumElementSide
                && frame.height >= Self.minimumElementSide
            let isHairline = min(frame.width, frame.height) >= Self.minimumHairlineThickness
                && max(frame.width, frame.height) >= Self.minimumHairlineLength
            guard isRegularElement || isHairline else { return }

            let key = "\(Int(frame.minX.rounded()))|\(Int(frame.minY.rounded()))|\(Int(frame.width.rounded()))|\(Int(frame.height.rounded()))"
            guard seenFrameKeys.insert(key).inserted else { return }
            frames.append(frame)
        }

        func rendersContent(_ view: UIView) -> Bool {
            if view is UILabel || view is UIImageView || view is UIControl { return true }
            if let backgroundColor = view.backgroundColor, backgroundColor.cgColor.alpha > 0.05 { return true }
            return false
        }

        func walkAccessibilityElements(of node: NSObject, depth: Int) {
            guard depth < Self.maximumWalkDepth, frames.count < Self.maximumElementCount else { return }

            if let elements = node.accessibilityElements, !elements.isEmpty {
                for case let element as NSObject in elements {
                    appendIfMeaningful(window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace))
                    walkAccessibilityElements(of: element, depth: depth + 1)
                }
                return
            }

            let elementCount = node.accessibilityElementCount()
            guard elementCount > 0, elementCount != NSNotFound else { return }
            for index in 0..<elementCount {
                guard let element = node.accessibilityElement(at: index) as? NSObject else { continue }
                appendIfMeaningful(window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace))
                walkAccessibilityElements(of: element, depth: depth + 1)
            }
        }

        func walkSubviews(of view: UIView, depth: Int) {
            guard depth < Self.maximumWalkDepth, frames.count < Self.maximumElementCount else { return }
            for subview in view.subviews {
                guard !subview.isHidden, subview.alpha > 0.01 else { continue }
                if rendersContent(subview) {
                    appendIfMeaningful(subview.convert(subview.bounds, to: window))
                }
                walkAccessibilityElements(of: subview, depth: depth + 1)
                walkSubviews(of: subview, depth: depth + 1)
            }
        }

        func walkLayers(of layer: CALayer, depth: Int) {
            guard depth < Self.maximumWalkDepth, frames.count < Self.maximumElementCount else { return }
            for sublayer in layer.sublayers ?? [] {
                guard !sublayer.isHidden, sublayer.opacity > 0.05 else { continue }
                // Gradient, shape, and text layers draw by nature without a contents
                // bitmap — gradient-filled SF Symbols render exactly this way.
                let drawsContent = sublayer.contents != nil
                    || sublayer is CAGradientLayer
                    || sublayer is CAShapeLayer
                    || sublayer is CATextLayer
                    || (sublayer.backgroundColor.map { $0.alpha > 0.05 } ?? false)
                if drawsContent {
                    appendIfMeaningful(window.layer.convert(sublayer.bounds, from: sublayer))
                }
                walkLayers(of: sublayer, depth: depth + 1)
            }
        }

        walkSubviews(of: window, depth: 0)
        walkLayers(of: window.layer, depth: 0)

        return frames.map { $0.normalized(in: windowBounds) }
    }
}
