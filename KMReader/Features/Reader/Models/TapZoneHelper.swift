//
// TapZoneHelper.swift
//
//

import Foundation

/// Centralized helper to determine tap zone actions based on TapZoneMode and tap location
enum TapZoneHelper {
  /// Determine the action for a tap at the given normalized location
  /// - Parameters:
  ///   - normalizedX: X position normalized to 0...1 (0 = left, 1 = right)
  ///   - normalizedY: Y position normalized to 0...1 (0 = top, 1 = bottom)
  ///   - tapZoneMode: The tap zone mode setting
  ///   - tapZoneInversionMode: The tap zone horizontal inversion setting
  ///   - readingDirection: The current reading direction (used when inversion mode is .auto)
  /// - Returns: The action to perform
  static func action(
    normalizedX: CGFloat,
    normalizedY: CGFloat,
    tapZoneMode: TapZoneMode,
    tapZoneInversionMode: TapZoneInversionMode,
    readingDirection: ReadingDirection,
    stripHeightFraction: CGFloat? = nil
  ) -> TapZoneAction {
    if tapZoneMode.isDisabled {
      return .toggleControls
    }

    if tapZoneMode == .tSplit {
      let frac = stripHeightFraction ?? 0.12
      if normalizedY <= frac { return .toggleControls }
      let leftHalf = normalizedX < 0.5
      let inverted = tapZoneInversionMode.isInverted(for: readingDirection)
      return (leftHalf != inverted) ? .previous : .next
    }

    let column = columnIndex(
      normalizedX: normalizedX,
      isInverted: tapZoneInversionMode.isInverted(for: readingDirection)
    )
    let row = rowIndex(normalizedY: normalizedY)
    return action(row: row, column: column, tapZoneMode: tapZoneMode)
  }

  static func action(
    row: Int,
    column: Int,
    tapZoneMode: TapZoneMode,
    tapZoneInversionMode: TapZoneInversionMode,
    readingDirection: ReadingDirection
  ) -> TapZoneAction {
    let effectiveColumn = tapZoneInversionMode.isInverted(for: readingDirection) ? 2 - column : column
    return action(row: row, column: effectiveColumn, tapZoneMode: tapZoneMode)
  }

  private static func action(row: Int, column: Int, tapZoneMode: TapZoneMode) -> TapZoneAction {
    guard !tapZoneMode.isDisabled else { return .toggleControls }

    switch tapZoneMode {
    case .none:
      return .toggleControls
    case .defaultLayout:
      switch column {
      case 0:
        return .previous
      case 1:
        return .toggleControls
      default:
        return .next
      }
    case .edge:
      if row == 1 && column == 1 {
        return .toggleControls
      }
      if row == 2 && column == 1 {
        return .previous
      }
      return .next
    case .kindle:
      if row == 0 {
        return .toggleControls
      }
      if column == 0 {
        return .previous
      }
      return .next
    case .lShape:
      if row == 1 && column == 1 {
        return .toggleControls
      }
      if row == 0 || (row == 1 && column == 0) {
        return .previous
      }
      return .next
    case .tSplit:
      return .toggleControls
    }
  }

  private static func columnIndex(normalizedX: CGFloat, isInverted: Bool) -> Int {
    let clampedX = min(max(normalizedX, 0), 0.999_999)
    let column = Int(clampedX * 3)
    return isInverted ? 2 - column : column
  }

  private static func rowIndex(normalizedY: CGFloat) -> Int {
    let clampedY = min(max(normalizedY, 0), 0.999_999)
    return Int(clampedY * 3)
  }
}
