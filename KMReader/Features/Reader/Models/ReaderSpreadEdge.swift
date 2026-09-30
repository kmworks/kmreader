//
// ReaderSpreadEdge.swift
//
//

import Foundation

/// Edge of a whole spread in single-page presentation, in reading order. The
/// spread opens at its start edge, pans freely between the two, and turns the
/// page only from the edge a step leaves through. Maps onto the split halves so
/// the committed side survives rebuilds through `ReaderPositionAnchor`.
enum ReaderSpreadEdge: Hashable {
  case start
  case end

  init?(splitPart: ReaderSplitPart?) {
    switch splitPart {
    case .first:
      self = .start
    case .second:
      self = .end
    case .both, nil:
      return nil
    }
  }

  var splitPart: ReaderSplitPart {
    switch self {
    case .start:
      return .first
    case .end:
      return .second
    }
  }
}
