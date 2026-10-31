//
// PanelImageLoading.swift
//
//

import CoreGraphics

/// Source of the original pre-split, decoded page image the detector runs on.
/// Abstracted so the orchestrator can be exercised with a controllable loader
/// (see the debug harness) without disk/network.
protocol PanelImageLoading: Sendable {
    func pageImage(bookId: String, page: BookPage) async -> CGImage?
}

extension PanelPageImageLoader: PanelImageLoading {}
