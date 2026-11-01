//
// PanelImageLoading.swift
//
//

import CoreGraphics

/// Source of the original pre-split, decoded page image the detector runs on.
protocol PanelImageLoading: Sendable {
  func pageImage(bookId: String, page: BookPage) async -> CGImage?
}

extension PanelPageImageLoader: PanelImageLoading {}
