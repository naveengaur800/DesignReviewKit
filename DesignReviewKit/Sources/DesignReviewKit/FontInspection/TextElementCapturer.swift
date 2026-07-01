//
//  TextElementCapturer.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 02/07/2026.
//

import UIKit

/// Collect on-screen text elements with their resolved typography at capture
/// time, pairing the always-available UILabel tier with the DEBUG-only SwiftUI
/// render-graph tier.
struct TextElementCapturer {

    /// Text capture output for one screen.
    struct Capture {
        let elements: [CapturedTextElement]
        /// Whether SwiftUI drew text this capture couldn't resolve — extraction
        /// is compiled out (Release) or broken by an OS update.
        let fontExtractionUnavailable: Bool
    }

    /// Plenty for any real screen while bounding session memory.
    private static let maximumTextElementCount = 300
    private static let maximumWalkDepth = 50
    private static let minimumElementSide: CGFloat = 1

    /// Capture the window's text elements in unit coordinates.
    func capture(in window: UIWindow) -> Capture {
        let windowBounds = window.bounds
        guard windowBounds.width > 0, windowBounds.height > 0 else {
            return Capture(elements: [], fontExtractionUnavailable: false)
        }

        var rawElements: [(frame: CGRect, string: String, fonts: [FontIdentity])] = []

        // UIKit tier: labels cover plain UIKit hosts plus UIKit-backed chrome
        // (navigation bar titles, button title labels).
        collectLabels(under: window, window: window, depth: 0, into: &rawElements)

        var swiftUITextCount = 0
        #if DEBUG
        for text in SwiftUITextExtraction.extractTexts(in: window) {
            rawElements.append((text.frame, text.string, text.fonts.map(FontIdentity.init)))
            swiftUITextCount += 1
        }
        #endif

        // Canary: SwiftUI drew text layers but extraction recovered none of them —
        // typography mode shows one explanatory banner instead of N empty cards.
        // False-positive limit: a SwiftUI screen whose drawing layers are all
        // shapes (no text at all) also trips this; harmless, as the banner only
        // appears in typography mode where there is nothing to inspect anyway.
        let fontExtractionUnavailable = swiftUITextCount == 0
            && containsSwiftUIDrawingLayers(window.layer, depth: 0)

        var elements: [CapturedTextElement] = []
        var seenElementKeys = Set<String>()
        for raw in rawElements {
            guard elements.count < Self.maximumTextElementCount else { break }
            guard raw.frame.intersects(windowBounds),
                  raw.frame.width >= Self.minimumElementSide,
                  raw.frame.height >= Self.minimumElementSide,
                  !raw.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            let key = "\(Int(raw.frame.minX.rounded()))|\(Int(raw.frame.minY.rounded()))|\(Int(raw.frame.width.rounded()))|\(Int(raw.frame.height.rounded()))|\(raw.string)"
            guard seenElementKeys.insert(key).inserted else { continue }

            elements.append(CapturedTextElement(
                id: UUID(),
                normalizedRect: raw.frame.normalized(in: windowBounds),
                string: raw.string,
                fonts: raw.fonts
            ))
        }

        return Capture(elements: elements, fontExtractionUnavailable: fontExtractionUnavailable)
    }

    // MARK: - UILabel Tier

    private func collectLabels(
        under view: UIView,
        window: UIWindow,
        depth: Int,
        into elements: inout [(frame: CGRect, string: String, fonts: [FontIdentity])]
    ) {
        guard depth < Self.maximumWalkDepth else { return }
        for subview in view.subviews {
            guard !subview.isHidden, subview.alpha > 0.01 else { continue }
            if let label = subview as? UILabel, let text = label.text, !text.isEmpty {
                elements.append((
                    frame: label.convert(label.bounds, to: window),
                    string: text,
                    fonts: fontIdentities(for: label)
                ))
            }
            collectLabels(under: subview, window: window, depth: depth + 1, into: &elements)
        }
    }

    /// Read the label's per-run fonts from attributed text when present,
    /// falling back to its plain font.
    private func fontIdentities(for label: UILabel) -> [FontIdentity] {
        if let runFonts = label.attributedText?.distinctRunFonts, !runFonts.isEmpty {
            return runFonts.map(FontIdentity.init)
        }
        return label.font.map { [FontIdentity(font: $0)] } ?? []
    }

    // MARK: - Canary

    /// Whether SwiftUI text/drawing layers are present — the signal that SwiftUI
    /// rendered content the extraction tier should have seen.
    private func containsSwiftUIDrawingLayers(_ layer: CALayer, depth: Int) -> Bool {
        guard depth < Self.maximumWalkDepth else { return false }
        for sublayer in layer.sublayers ?? [] {
            if String(reflecting: type(of: sublayer)).contains("CGDrawingLayer") {
                return true
            }
            if containsSwiftUIDrawingLayers(sublayer, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}
