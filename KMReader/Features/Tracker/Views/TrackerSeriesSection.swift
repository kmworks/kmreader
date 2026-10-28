//
// TrackerSeriesSection.swift
//

import SwiftUI

struct TrackerSeriesSection: View {
  let seriesId: String
  let libraryId: String
  let seriesTitle: String

  @State private var links: [TrackerLink] = []
  @State private var showManage = false

  var body: some View {
    #if os(iOS) || os(macOS)
      if TrackerCapabilityStore.shared.isSupported,
        TrackerCapabilityStore.shared.allows(libraryId: libraryId),
        !links.isEmpty
      {
        VStack(alignment: .leading, spacing: 8) {
          Text(String(localized: "Trackers"))
            .font(.headline)
          Button {
            showManage = true
          } label: {
            HStack {
              ForEach(links) { link in
                Text(link.provider.displayName)
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(LayoutConfig.neutralFillColor, in: Capsule())
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
          }
          .adaptiveButtonStyle(.plain)
        }
        .task(id: seriesId) {
          await load()
        }
        .sheet(
          isPresented: $showManage,
          onDismiss: {
            Task { await load() }
          }
        ) {
          TrackerSeriesSheet(
            seriesId: seriesId,
            libraryId: libraryId,
            seriesTitle: seriesTitle
          )
        }
      }
    #endif
  }

  private func load() async {
    guard !AppConfig.isOffline else { return }
    do {
      links = try await TrackerService.getLinks(seriesId: seriesId)
    } catch {
      links = []
    }
  }
}
