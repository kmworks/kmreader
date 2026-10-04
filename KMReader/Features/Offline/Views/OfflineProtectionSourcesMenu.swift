//
// OfflineProtectionSourcesMenu.swift
//
//

import SwiftUI

struct OfflineProtectionSourcesMenu: View {
  let sources: [OfflineProtectionSource]

  var body: some View {
    if !sources.isEmpty {
      Menu {
        ForEach(sources) { source in
          NavigationLink(value: destination(for: source)) {
            Label(source.displayName, systemImage: source.kind.systemImage)
          }
        }
      } label: {
        Image(systemName: "lock.fill")
          .font(.caption)
          .padding(4)
          .contentShape(Rectangle())
      }
      .foregroundColor(.secondary)
      .lineLimit(1)
      .accessibilityLabel(Text("Protected"))
    }
  }

  private func destination(for source: OfflineProtectionSource) -> NavDestination {
    switch source.kind {
    case .series:
      return .seriesDetail(seriesId: source.sourceId)
    case .readList:
      return .readListDetail(readListId: source.sourceId)
    }
  }
}
