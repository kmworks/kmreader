//
// SeriesDetailChipsView.swift
//
//

import SwiftUI

/// Genre, tag, and external link chip flows of the series detail page.
struct SeriesDetailChipsView: View {
  let series: Series

  private let collapsedLinkLimit = 6

  var body: some View {
    DetailChipFlow(items: genreItems, collapsedLimit: collapsedLinkLimit, glass: false)
    DetailChipFlow(items: tagItems, collapsedLimit: collapsedLinkLimit, glass: false)
    DetailChipFlow(items: linkItems, collapsedLimit: collapsedLinkLimit)
  }

  private var genreItems: [DetailChipFlow.Item] {
    sortedGenres.map {
      .init(
        title: $0,
        systemImage: "theatermasks",
        destination: .navigate(MetadataFilterHelper.seriesDestinationForGenre($0))
      )
    }
  }

  private var tagItems: [DetailChipFlow.Item] {
    combinedTagItems.map {
      .init(
        title: $0,
        systemImage: "tag",
        destination: .navigate(MetadataFilterHelper.seriesDestinationForTag($0))
      )
    }
  }

  private var linkItems: [DetailChipFlow.Item] {
    (series.metadata.links ?? []).compactMap { link in
      URL(string: link.url).map {
        .init(title: link.label, systemImage: "link", destination: .external($0))
      }
    }
  }

  private var sortedGenres: [String] {
    (series.metadata.genres ?? []).localizedSorted()
  }

  /// Series tags first (sorted), then book-only tags (sorted) — preserves web UI behavior
  private var combinedTagItems: [String] {
    let seriesTags = (series.metadata.tags ?? []).filter { !$0.isEmpty }.localizedSorted()
    let bookTags = (series.booksMetadata.tags ?? []).filter { !$0.isEmpty }

    let seriesSet = Set(seriesTags)
    let bookOnly = Set(bookTags).subtracting(seriesSet).localizedSorted()

    return seriesTags + bookOnly
  }
}
