//
// EpubBookPageProgress.swift
//
//

import Foundation

/// Book-wide page position for reader chrome. Unmeasured chapters contribute
/// text-weight estimates until their layout produces an exact page count.
nonisolated struct EpubBookPageProgress: Equatable, Sendable {
  let currentPage: Int
  let totalPages: Int
}
