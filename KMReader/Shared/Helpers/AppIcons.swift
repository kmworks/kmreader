//
// AppIcons.swift
//
//

import Foundation

/// Shared SF Symbol names for cross-feature meanings. One-off decorative
// glyphs stay inline at their call site.
nonisolated enum AppIcon {
  // MARK: - Common Actions

  static let edit = "pencil"
  static let delete = "trash"
  static let share = "square.and.arrow.up"
  static let refresh = "arrow.clockwise"
  static let reset = "arrow.counterclockwise"
  static let analyze = "waveform.path.ecg"
  static let search = "magnifyingglass"
  static let filter = "line.3.horizontal.decrease"
  static let filterCircle = "line.3.horizontal.decrease.circle"
  static let sort = "arrow.up.arrow.down"
  static let more = "ellipsis"
  static let close = "xmark"
  static let confirm = "checkmark"
  static let add = "plus"
  static let addRow = "plus.circle.fill"
  static let details = "info.circle"
  static let externalLink = "arrow.up.right.square"
  static let copy = "doc.on.doc"
  static let settings = "gearshape"
  static let peek = "eye.slash"

  // MARK: - Reading Actions

  static let markRead = "checkmark.circle"
  static let markUnread = "circle"
  static let pageJump = "arrow.right.to.line"

  // MARK: - Offline Downloads

  static let download = "icloud.and.arrow.down"
  /// Filled in every context: part of the status's identity.
  static let downloaded = "checkmark.icloud.fill"
  static let downloadPartial = "icloud"
  static let downloadFailed = "exclamationmark.circle.fill"
  static let clearCache = "xmark.circle"

  // MARK: - Errors

  static let loadError = "exclamationmark.triangle"
}
