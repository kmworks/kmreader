//
// ReaderRotation.swift
//

import CoreGraphics
import Foundation

nonisolated enum ReaderRotation: Int, CaseIterable, Hashable, Codable, Sendable {
  case none = 0
  case degrees90 = 90
  case degrees180 = 180
  case degrees270 = 270

  var degrees: Int {
    rawValue
  }

  var displayName: String {
    "\(degrees)°"
  }

  var swapsDimensions: Bool {
    self == .degrees90 || self == .degrees270
  }

  func rotatedSize(_ size: CGSize) -> CGSize {
    guard swapsDimensions else { return size }
    return CGSize(width: size.height, height: size.width)
  }
}
