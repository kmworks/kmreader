//
// LibraryBrowseScope.swift
//
//

import Foundation

/// Library scope of a browse surface (Dashboard, iPhone Library tab):
/// `.pinned` renders the pinned aggregate (`dashboard.libraryIds`, empty =
/// all libraries), `.all` ignores the pins, `.library(id)` scopes to a single
/// library. Session-only view state — it never persists.
enum LibraryBrowseScope: Hashable {
  case pinned
  case all
  case library(String)

  var libraryId: String? {
    if case .library(let id) = self { return id }
    return nil
  }

  /// The library ids the scope resolves to (empty = no library filter).
  func resolvedIds(pinned: [String]) -> [String] {
    switch self {
    case .pinned:
      return pinned
    case .all:
      return []
    case .library(let id):
      return [id]
    }
  }

  /// Display title: All Libraries, the pinned count (or the single covered
  /// library's name), or the scoped library's name. Nil when the scoped
  /// library is not in the list, or (for pinned) before the list arrives —
  /// a count rendered from an empty list would flash "0 Libraries".
  func title(pinnedIds: [String], libraries: [SidebarLibraryItem]) -> String? {
    switch self {
    case .all:
      return String(localized: "All Libraries")
    case .pinned:
      guard !libraries.isEmpty else { return nil }
      let pinned = Set(pinnedIds)
      let covered = pinned.isEmpty ? libraries : libraries.filter { pinned.contains($0.libraryId) }
      if covered.count == 1, let name = covered.first?.name {
        return name
      }
      return String.localizedStringWithFormat(
        String(localized: "library.scope.librariesCount", defaultValue: "%lld Libraries"),
        covered.count)
    case .library(let id):
      return libraries.first(where: { $0.libraryId == id })?.name
    }
  }

  /// Metrics of the covered libraries: the server's all-libraries entry for
  /// the full set (overlapping roots make client-side sums overstate file
  /// size), a client-side sum for pinned subsets, the library itself for a
  /// single-library scope.
  func facts(
    pinnedIds: [String],
    libraries: [SidebarLibraryItem],
    allLibrariesEntry: SidebarLibraryItem?
  ) -> SidebarLibraryItem? {
    switch self {
    case .all:
      return Self.fullSetFacts(libraries: libraries, allLibrariesEntry: allLibrariesEntry)
    case .pinned:
      let pinned = Set(pinnedIds)
      if pinned.isEmpty {
        return Self.fullSetFacts(libraries: libraries, allLibrariesEntry: allLibrariesEntry)
      }
      return SidebarLibraryItem.aggregating(libraries.filter { pinned.contains($0.libraryId) })
    case .library(let id):
      return libraries.first(where: { $0.libraryId == id })
    }
  }

  private static func fullSetFacts(
    libraries: [SidebarLibraryItem],
    allLibrariesEntry: SidebarLibraryItem?
  ) -> SidebarLibraryItem? {
    if let entry = allLibrariesEntry, entry.hasAnyMetrics {
      return entry
    }
    return SidebarLibraryItem.aggregating(libraries)
  }
}
