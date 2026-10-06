//
// ReadListBookCountView.swift
//
//

import SwiftUI

/// Book count and ordering line shown inside the read list detail action
/// card.
struct ReadListBookCountView: View {
  let readList: ReadList

  @Environment(\.detailHeroCentered) private var heroCentered

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(readList.bookIds.count) books")
        .font(.subheadline.weight(.semibold))

      if readList.ordered {
        Label("Ordered", systemImage: AppIcon.sort)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: heroCentered ? .center : .leading)
  }
}
