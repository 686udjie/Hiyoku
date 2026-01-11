//
//  UIConstants.swift
//  Hiyoku
//
//  Created by 686udjie on 01/11/26.
//

import SwiftUI

/// Shared UI constants and utilities
enum UIConstants {
    /// Standard gradient used for overlay effects on images
    static let imageOverlayGradient = Gradient(
        colors: (0...24).map { offset -> Color in
            let ratio = CGFloat(offset) / 24
            return Color.black.opacity(0.7 * pow(ratio, CGFloat(3)))
        }
    )
}
