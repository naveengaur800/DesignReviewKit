//
//  DesignTokenResolving.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 02/07/2026.
//

/// Map resolved rendering values to the host's design-system names.
///
/// Supply a resolver through ``DesignInspector/Configuration/tokenResolver``
/// and typography mode shows your token names in place of raw readings:
/// `headingM · brandBlue` instead of `GTAmerica-Bold · 19pt · #0088FF`.
/// The copy affordance keeps both forms for precision.
///
/// Implement only the mappings you have — every method defaults to `nil`,
/// which falls back to the raw reading for that value.
public protocol DesignTokenResolving: Sendable {

    /// - Returns: The host's name for a rendered text color
    ///   (e.g. `#0088FF` → "brandBlue"), or `nil` when it matches no token.
    func colorName(for color: TextColor) -> String?

    /// - Returns: The host's name for a rendered font
    ///   (e.g. `GTAmerica-Bold · 19pt` → "headingM"), or `nil` when it
    ///   matches no token.
    func fontName(for font: FontIdentity) -> String?
}

public extension DesignTokenResolving {

    func colorName(for color: TextColor) -> String? { nil }

    func fontName(for font: FontIdentity) -> String? { nil }
}
