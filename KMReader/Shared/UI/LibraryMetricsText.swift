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

  /// Facts line: file size first, then series/books counts.
  static func sizeAndMetrics(for library: SidebarLibraryItem) -> Text? {
    var parts: [Text] = []
    if let fileSize = library.fileSize {
      parts.append(Text(fileSize.humanReadableFileSize))
    }
    if let metrics = metrics(for: library, includeSidecars: false) {
      parts.append(metrics)
    }
    return join(parts, separator: " · ")
  }

  /// Scope caption trailing a content-type chip: the title in medium weight,
  /// then the facts line in secondary.
  static func scopeCaption(title: String, facts: Text?) -> Text {
    var text = Text(title).fontWeight(.medium)
    if let facts {
      text =
        text + Text(" · ").foregroundColor(.secondary)
        + facts.foregroundColor(.secondary)
    }
    return text
  }

  /// Per-library metrics: series and books on one line, plus sidecars for
  /// list rows that want them.
  static func metrics(for library: SidebarLibraryItem, includeSidecars: Bool = true) -> Text? {
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
    if includeSidecars, let sidecarsCount = library.sidecarsCount {
      parts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.sidecars", defaultValue: "%lld sidecars"),
            Int(sidecarsCount))))
    }

    return join(parts, separator: " · ")
  }
}
