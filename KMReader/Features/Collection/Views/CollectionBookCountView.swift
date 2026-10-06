//
// CollectionBookCountView.swift
//
//

import SwiftUI

/// Series count and ordering line shown inside the collection detail action
/// card.
struct CollectionBookCountView: View {
  let collection: SeriesCollection

  @Environment(\.detailHeroCentered) private var heroCentered

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(collection.seriesIds.count) series")
        .font(.subheadline.weight(.semibold))

      if collection.ordered {
        Label("Ordered", systemImage: AppIcon.sort)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: heroCentered ? .center : .leading)
  }
}
