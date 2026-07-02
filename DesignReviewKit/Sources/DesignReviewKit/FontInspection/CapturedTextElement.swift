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

/// A resolved font as it was actually drawn: face, family, size, and ink after
/// Dynamic Type and style resolution.
nonisolated struct FontIdentity: Sendable, Hashable {
    /// PostScript face name, e.g. `GTAmerica-Bold` or `.SFUI-Semibold`.
    let faceName: String

    let familyName: String

    let pointSize: CGFloat

    /// Flat fill color of the run as rendered; `nil` when none was recorded.
    /// Gradient and material fills report their base ink, not the effect.
    let color: TextColor?

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

    /// One-line identity for the card and the copy affordance,
    /// e.g. "GTAmerica-Bold · 19pt · #1C1C1E".
    var summary: String {
        var parts = ["\(displayName) · \(formattedPointSize)"]
        if let color {
            parts.append(color.hexString)
        }
        return parts.joined(separator: " · ")
    }

    private var formattedPointSize: String {
        pointSize == pointSize.rounded()
            ? "\(Int(pointSize))pt"
            : String(format: "%.1fpt", pointSize)
    }
}

/// Resolved sRGB text color as drawn at capture time.
nonisolated struct TextColor: Sendable, Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    /// Uppercase hex like "#1C1C1E", with an alpha pair appended only when
    /// the color is translucent, e.g. "#3C3C4399". Wide-gamut components
    /// clamp into sRGB range for the readout; the stored components stay
    /// exact, so the swatch renders the true color.
    var hexString: String {
        func byte(_ value: CGFloat) -> Int {
            Int((max(0, min(1, value)) * 255).rounded())
        }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha < 0.999 ? base + String(format: "%02X", byte(alpha)) : base
    }
}

nonisolated extension TextColor {

    /// Build from a resolved UIKit color; `nil` when it has no RGBA form.
    init?(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

nonisolated extension FontIdentity {

    /// Build the identity from a resolved UIKit font and optional run color.
    init(font: UIFont, color: UIColor?) {
        self.init(
            faceName: font.fontName,
            familyName: font.familyName,
            pointSize: font.pointSize,
            color: color.flatMap(TextColor.init)
        )
    }

    /// Copy with `fallback` substituted when the run recorded no color —
    /// UILabel runs without an explicit color render with the label's color.
    func fillingMissingColor(with fallback: TextColor?) -> FontIdentity {
        guard color == nil else { return self }
        return FontIdentity(faceName: faceName, familyName: familyName, pointSize: pointSize, color: fallback)
    }
}

nonisolated extension NSAttributedString {

    /// Collect each distinct run's typography — font plus flat color — in run
    /// order: the single definition of "what this text renders with" for
    /// every extraction tier.
    var distinctRunIdentities: [FontIdentity] {
        var identities: [FontIdentity] = []
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, _, _ in
            guard let font = attributes[.font] as? UIFont else { return }
            let identity = FontIdentity(font: font, color: attributes[.foregroundColor] as? UIColor)
            if !identities.contains(identity) {
                identities.append(identity)
            }
        }
        return identities
    }
}
