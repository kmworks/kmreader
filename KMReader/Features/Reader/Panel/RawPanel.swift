//
// RawPanel.swift
//
//

import Foundation

/// One raw detector candidate: a normalized `[0,1]` box plus its confidence. Confidence is
/// kept only long enough for suppression; it never crosses into the reader contract.
struct RawPanel: Sendable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
  let confidence: Double
}
