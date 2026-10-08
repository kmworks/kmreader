//
// CoverAspectRatio.swift
//
//

import CoreGraphics

enum CoverAspectRatio {
  nonisolated static let heightToWidth: CGFloat = CGFloat(Double(2).squareRoot())
  nonisolated static let widthToHeight: CGFloat = 1 / heightToWidth
}
