//
// LibraryMetricsText.swift
//
//

import SwiftUI

/// Shared text builders for library rows: metrics lines and file sizes.
enum LibraryMetricsText {
  static func join(_ parts: [Text], separator: String) -> Text? {
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { result, part in
      result + Text(separator) + part
    }
  }

  static func formatFileSize(_ bytes: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
  }

  /// Facts line: file size first, then series/books/sidecars counts.
  static func sizeAndMetrics(for library: SidebarLibraryItem) -> Text? {
    var parts: [Text] = []
    if let fileSize = library.fileSize {
      parts.append(Text(fileSize.humanReadableFileSize))
    }
    if let metrics = metrics(for: library) {
      parts.append(metrics)
    }
    return join(parts, separator: " · ")
  }

  /// Per-library metrics: series, books, and sidecars on one line.
  static func metrics(for library: SidebarLibraryItem) -> Text? {
    var parts: [Text] = []

    if let seriesCount = library.seriesCount {
      parts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.series", defaultValue: "%lld series"),
            Int(seriesCount))))
    }
    if let booksCount = library.booksCount {
      parts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.books", defaultValue: "%lld books"),
            Int(booksCount))))
    }
    if let sidecarsCount = library.sidecarsCount {
      parts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.sidecars", defaultValue: "%lld sidecars"),
            Int(sidecarsCount))))
    }

    return join(parts, separator: " · ")
  }

  /// All-libraries metrics: the per-library line plus a collections/read lists
  /// line below it.
  static func allLibrariesMetrics(for entry: SidebarLibraryItem) -> Text? {
    var lines: [Text] = []

    if let firstLine = metrics(for: entry) {
      lines.append(firstLine)
    }

    var secondLineParts: [Text] = []
    if let collectionsCount = entry.collectionsCount {
      secondLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.collections", defaultValue: "%lld collections"),
            Int(collectionsCount))))
    }
    if let readlistsCount = entry.readlistsCount {
      secondLineParts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.readlists", defaultValue: "%lld read lists"),
            Int(readlistsCount))))
    }
    if let secondLine = join(secondLineParts, separator: " · ") {
      lines.append(secondLine)
    }

    return join(lines, separator: "\n")
  }
}
