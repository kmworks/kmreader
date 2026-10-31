//
// VisionTextProvider.swift
//
//

import CoreGraphics

/// Locates text LINES on a page as normalized [0,1] boxes (top-left origin) via OCR, independent of
/// the panel detector. Used by panel mode's readability paths (wide-panel sub-views and the panel-less
/// bubble-walk): the line boxes seed the wide split, and their count inside each detector text bubble
/// gives the readability gate its per-bubble line count. An EMPTY result is also the routing signal
/// that a page is vertical CJK (OCR reads horizontal/Latin only). A nil provider disables the readability
/// paths with no other code change.
protocol VisionTextProvider: Sendable {
    var version: String { get }
    /// Normalized OCR line boxes for a page, unordered. Empty on failure or vertical CJK.
    func detectText(image: CGImage) async -> [PanelRect]
}
