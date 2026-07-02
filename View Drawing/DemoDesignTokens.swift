//
//  DemoDesignTokens.swift
//  View Drawing
//
//  Created by Naveen Gaur on 02/07/2026.
//

import DesignReviewKit
import Foundation

/// Demo design-token table: map the showcase screen's rendered values to
/// token names, demonstrating the kit's `DesignTokenResolving` hook.
/// Unmapped values fall back to raw readings (face, size, hex) in the card.
struct DemoDesignTokens: DesignTokenResolving {

    func colorName(for color: TextColor) -> String? {
        switch color.hexString {
        case "#0088FF": "brandBlue"
        case "#3C3C4399": "textSecondary"
        default: nil
        }
    }

    func fontName(for font: FontIdentity) -> String? {
        font.faceName == "Avenir-Heavy" && font.pointSize == 13 ? "linkS" : nil
    }
}
