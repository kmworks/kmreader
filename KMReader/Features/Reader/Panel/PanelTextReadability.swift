//
// PanelTextReadability.swift
//
// The settled text-readability metric shared by panel mode's readability paths. Bubbles come from the
// detector `text` class (clean, region-level, all scripts, ignores SFX); LINES come from OCR
// (`VisionTextProvider`, horizontal/Latin only). Routing is by the OCR-empty signal — OCR returns lines
// => LATIN/horizontal; OCR empty + detector has text => CJK/vertical (Komga language metadata is
// unreliable, so we never use it). "Readable" means the per-line/char text, shown at whole-page zoom,
// renders above `readFloor` of the page height; below it the page needs a zoom walk.
//
// Latin per-line height = bubble height / OCR lines inside it, measured ONLY over bubbles where OCR
// found a line (a bubble OCR missed has no measurable font size and must not inflate the median). CJK
// per-char size = min(width, height) of each bubble (no OCR line count available). All boxes are
// normalized [0,1], so a height IS already its fraction of page height.
//

import Foundation

nonisolated enum PanelTextReadability {
  /// A detector text box whose smaller side is below this fraction of the page is a speck, not a
  /// bubble worth measuring or walking.
  static let minBubble = 0.012
  /// Per-line/char height below this fraction of page height (at whole-page zoom) reads too small.
  static let readFloor = 0.022

  /// Detector text boxes filtered to real bubbles (specks dropped).
  static func bubbles(_ texts: [PanelRect]) -> [PanelRect] {
    texts.filter { min($0.width, $0.height) >= minBubble }
  }

  /// True when the page's text is comfortably readable at whole-page zoom (so no walk is needed).
  /// `bubbles` are the (already speck-filtered) detector text boxes; `ocrLines` the OCR line boxes.
  static func isReadable(bubbles: [PanelRect], ocrLines: [PanelRect]) -> Bool {
    legibility(bubbles: bubbles, ocrLines: ocrLines) >= readFloor
  }

  /// Median per-line/char normalized height. Returns 1.0 (trivially readable) when nothing is
  /// measurable, so an empty/odd page degrades to "no walk" rather than a spurious walk.
  static func legibility(bubbles: [PanelRect], ocrLines: [PanelRect]) -> Double {
    var perLine: [Double] = []
    if ocrLines.isEmpty {
      // CJK / vertical: OCR is blind, so use the bubble's smaller side as the character size.
      for bubble in bubbles { perLine.append(min(bubble.width, bubble.height)) }
    } else {
      // Latin / horizontal: frame height divided by the OCR lines inside it.
      for bubble in bubbles {
        let lines = ocrLines.filter { contained($0, in: bubble) >= 0.5 }.count
        if lines > 0 { perLine.append(bubble.height / Double(lines)) }
      }
    }
    return perLine.isEmpty ? 1.0 : median(perLine)
  }

  // MARK: - Geometry

  /// Fraction of `inner`'s area that lies inside `outer`.
  private static func contained(_ inner: PanelRect, in outer: PanelRect) -> Double {
    let iw = max(0, min(inner.x + inner.width, outer.x + outer.width) - max(inner.x, outer.x))
    let ih = max(0, min(inner.y + inner.height, outer.y + outer.height) - max(inner.y, outer.y))
    let area = max(0, inner.width) * max(0, inner.height)
    return area > 0 ? (iw * ih) / area : 0
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
  }
}
