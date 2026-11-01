//
// PanelSequence.swift
//
//

import Foundation

enum PanelSequence: Equatable, Sendable {
  case empty
  case panels([PanelRect])
  /// A single content beat with NO trailing whole-page bookend, so the walk is `[leading whole-page
  /// · beat]` and stepping forward off it turns the page directly. Used for a splash (one framed
  /// panel) and a near-splash (a panel-less page's slight-zoom crop).
  case splash(PanelRect)

  var isEmpty: Bool {
    if case .empty = self { return true }
    return false
  }

  /// Total walk positions. A normal page is N+2 (leading whole-page · N panels · trailing whole-
  /// page); a splash is 2 (leading whole-page · splash, no trailing bookend). Returns 0 for the
  /// empty sequence (panel mode cannot engage).
  var count: Int {
    switch self {
    case .empty:
      return 0
    case .panels(let rects):
      return rects.count + 2
    case .splash:
      return 2
    }
  }

  /// Panel rect for a cursor index, or nil for a whole-page position.
  /// Normal page: index 0 = leading whole-page; 1…N = panel[0…N-1]; N+1 = trailing whole-page.
  /// Splash: index 0 = leading whole-page; index 1 = the splash panel (no trailing position).
  subscript(index: Int) -> PanelRect? {
    switch self {
    case .empty:
      return nil
    case .panels(let rects):
      guard index >= 0 && index < rects.count + 2 else { return nil }
      if index == 0 || index == rects.count + 1 { return nil }
      return rects[index - 1]
    case .splash(let rect):
      return index == 1 ? rect : nil
    }
  }
}
