//
// EpubScrubPreview.swift
//
//

import Foundation

/// Resolved destination previewed while scrubbing the EPUB progress bar.
nonisolated struct EpubScrubPreview: Equatable, Sendable {
  let fraction: Double
  let chapterIndex: Int
  let pageIndex: Int
  let chapterTitle: String
  let bookPage: Int
  let totalPages: Int
}
