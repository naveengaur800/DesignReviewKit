//
//  CapturedTextElement.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 02/07/2026.
//

import UIKit

/// One rendered text element captured with the screen, for typography mode.
nonisolated struct CapturedTextElement: Identifiable, Sendable, Equatable {
    let id: UUID

    /// Frame in unit coordinates relative to the capture.
    let normalizedRect: CGRect

    /// The string as rendered at capture time.
    let string: String

    /// Resolved fonts, one per distinct styled run in run order.
    /// Empty when the element was detected but its font couldn't be extracted.
    let fonts: [FontIdentity]
}

/// A resolved font as it was actually drawn: face, family, and size after
/// Dynamic Type and style resolution.
nonisolated struct FontIdentity: Sendable, Hashable {
    /// PostScript face name, e.g. `GTAmerica-Bold` or `.SFUI-Semibold`.
    let faceName: String

    let familyName: String

    let pointSize: CGFloat

    /// Face name in designer language: system internals like `.SFUI-Semibold`
    /// read as "SF Pro Semibold"; custom faces stay verbatim.
    var displayName: String {
        if faceName.hasPrefix(".SFUI") {
            let weight = faceName.split(separator: "-").dropFirst().joined(separator: " ")
            return weight.isEmpty || weight == "Regular" ? "SF Pro" : "SF Pro \(weight)"
        }
        if faceName.hasPrefix(".") {
            return String(faceName.dropFirst())
        }
        return faceName
    }

    /// One-line identity for the card and the copy affordance, e.g. "GTAmerica-Bold · 19pt".
    var summary: String {
        "\(displayName) · \(formattedPointSize)"
    }

    private var formattedPointSize: String {
        pointSize == pointSize.rounded()
            ? "\(Int(pointSize))pt"
            : String(format: "%.1fpt", pointSize)
    }
}

nonisolated extension FontIdentity {

    /// Build the identity from a resolved UIKit font.
    init(font: UIFont) {
        self.init(faceName: font.fontName, familyName: font.familyName, pointSize: font.pointSize)
    }
}

nonisolated extension NSAttributedString {

    /// Collect each distinct run font in run order — the single definition of
    /// "which fonts does this text render with" for every extraction tier.
    var distinctRunFonts: [UIFont] {
        var fonts: [UIFont] = []
        enumerateAttribute(.font, in: NSRange(location: 0, length: length)) { value, _, _ in
            guard let font = value as? UIFont else { return }
            let isKnown = fonts.contains { $0.fontName == font.fontName && $0.pointSize == font.pointSize }
            if !isKnown {
                fonts.append(font)
            }
        }
        return fonts
    }
}
