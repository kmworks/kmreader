//
// OfflineProtectionStatusChip.swift
//
//

import SwiftUI

struct OfflineProtectionStatusChip: View {
  let label: String
  let systemImage: String
  let spinning: Bool
  let sources: [OfflineProtectionSource]

  var body: some View {
    if sources.isEmpty {
      DownloadStatusIcon(systemName: systemImage, spinning: spinning)
        .font(.caption)
        .accessibilityLabel(label)
    } else {
      Menu {
        ForEach(sources) { source in
          NavigationLink(value: destination(for: source)) {
            Label(source.displayName, systemImage: source.kind.systemImage)
          }
        }
      } label: {
        HStack(spacing: 3) {
          DownloadStatusIcon(systemName: systemImage, spinning: spinning)
          Image(systemName: "lock.fill")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(4)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
      }
      .buttonStyle(.plain)
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
