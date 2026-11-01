//
// PanelStepOutcome.swift
//
//

import Foundation

/// Result of a `step`: either the controller handled it internally (zoomed within the
/// page) or the host must turn the page (the controller has recorded the direction so
/// the post-turn `updateCurrentPage` lands the cursor on the right whole-page bookend).
enum PanelStepOutcome: Equatable {
  case handled
  case turnPage(forward: Bool)
}
