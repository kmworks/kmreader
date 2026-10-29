//
// TrackerBindingRow.swift
//

import Flow
import SwiftUI

struct TrackerBindingRow: View {
  let group: TrackerLinkGroup
  let onUnlink: (TrackerLink) -> Void

  @AppStorage("currentAccount") private var current: Current = .init()
  @Environment(\.openURL) private var openURL
  @State private var seriesTitle: String?

  var body: some View {
    NavigationLink(value: NavDestination.seriesDetail(seriesId: group.seriesId)) {
      HStack(spacing: 12) {
        ThumbnailImage(
          id: group.seriesId,
          type: .series,
          shadowStyle: .none,
          width: 40,
          cornerRadius: 4,
          isTransitionSource: false
        )

        VStack(alignment: .leading, spacing: 6) {
          Text(seriesTitle ?? group.links.first?.displayTitle ?? group.seriesId)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
          HFlow(spacing: 6) {
            ForEach(group.links) { link in
              TrackerBindingChip(link: link)
            }
          }
        }
      }
      .contentShape(Rectangle())
    }
    .contextMenu {
      ForEach(group.links) { link in
        Section(link.provider.displayName) {
          if let url = link.provider.entryURL(trackId: link.trackId) {
            Button {
              openURL(url)
            } label: {
              Label(String(localized: "Open on Website"), systemImage: "safari")
            }
          }
          Button(role: .destructive) {
            onUnlink(link)
          } label: {
            Label(String(localized: "Unlink"), systemImage: "link.badge.minus")
          }
        }
      }
    }
    .task(id: "\(current.instanceId)|\(group.seriesId)") {
      await loadTitle()
    }
  }

  private func loadTitle() async {
    guard let database = try? await DatabaseOperator.database() else { return }
    let item = try? await database.fetchSeriesDisplayItem(
      seriesId: group.seriesId,
      instanceId: current.instanceId
    )
    seriesTitle = item?.series.metadata.title
  }
}
