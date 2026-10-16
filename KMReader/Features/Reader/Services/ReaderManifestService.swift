//
// ReaderManifestService.swift
//
//

import Foundation
import OSLog
import UniformTypeIdentifiers

struct ReaderManifestService {
  let bookId: String

  /// Parse Table of Contents from manifest
  func parseTOC(manifest: DivinaManifest) async -> [ReaderTOCEntry] {
    guard let manifestTOC = manifest.toc, !manifestTOC.isEmpty else {
      return []
    }

    // Build href to page number mapping from reading order
    var hrefToPageNumber: [String: Int] = [:]
    for (index, resource) in manifest.readingOrder.enumerated() {
      if let canonicalURL = resolvedManifestURL(from: resource.href) {
        hrefToPageNumber[canonicalURL.absoluteString] = index + 1
      }
    }

    return buildTOCEntries(manifestTOC: manifestTOC, hrefPageMap: hrefToPageNumber)
  }

  private func buildTOCEntries(
    manifestTOC: [DivinaManifestLink],
    hrefPageMap: [String: Int]
  ) -> [ReaderTOCEntry] {
    var entries: [ReaderTOCEntry] = []

    for item in manifestTOC {
      guard
        let resolvedURL = resolvedManifestURL(from: item.href),
        let pageNumber = hrefPageMap[resolvedURL.absoluteString]
      else {
        continue
      }

      let pageIndex = pageNumber - 1
      let trimmedTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let title =
        trimmedTitle.isEmpty
        ? localizedPageLabel(pageNumber)
        : trimmedTitle

      let children: [ReaderTOCEntry]? =
        if let itemChildren = item.children, !itemChildren.isEmpty {
          buildTOCEntries(manifestTOC: itemChildren, hrefPageMap: hrefPageMap)
        } else {
          nil
        }

      entries.append(ReaderTOCEntry(title: title, pageIndex: pageIndex, children: children))
    }

    return entries
  }

  private func resolvedManifestURL(from href: String) -> URL? {
    guard !href.isEmpty else { return nil }
    if let absoluteURL = URL(string: href), absoluteURL.scheme != nil {
      return absoluteURL
    }
    guard !AppConfig.current.serverURL.isEmpty, let baseURL = URL(string: AppConfig.current.serverURL) else {
      return nil
    }
    if let relativeURL = URL(string: href, relativeTo: baseURL) {
      return relativeURL.absoluteURL
    }
    return nil
  }

  private func localizedPageLabel(_ pageNumber: Int) -> String {
    let format = String(localized: "Page %d", bundle: .main, comment: "Fallback TOC title")
    return String.localizedStringWithFormat(format, pageNumber)
  }
}
