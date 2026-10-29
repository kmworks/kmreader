//
// TrackerSeriesSection.swift
//

import Flow
import SwiftUI

struct TrackerSeriesSection: View {
  let seriesId: String
  let libraryId: String
  let seriesTitle: String
  let alternateTitles: [String]

  @State private var links: [TrackerLink] = []
  @State private var states: [TrackerProvider: TrackerRemoteState] = [:]
  @State private var providersRequiringLogin: Set<TrackerProvider> = []
  @State private var editingLink: TrackerLink?
  @State private var showManage = false

  var body: some View {
    #if os(iOS) || os(macOS)
      if TrackerCapabilityStore.shared.isSupported,
        TrackerCapabilityStore.shared.allows(libraryId: libraryId)
      {
        HFlow(itemSpacing: 8) {
          ForEach(links) { link in
            Button {
              editingLink = link
            } label: {
              TrackerLinkChip(
                link: link,
                state: states[link.provider],
                requiresLogin: providersRequiringLogin.contains(link.provider)
              )
            }
            .adaptiveButtonStyle(.plain)
          }
          if links.count < TrackerProvider.allCases.count {
            Button {
              showManage = true
            } label: {
              Label(String(localized: "Add Tracker"), systemImage: "plus")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
            }
            .adaptiveButtonStyle(.plain)
          }
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
            seriesTitle: seriesTitle,
            alternateTitles: alternateTitles
          )
        }
        .sheet(item: $editingLink) { link in
          TrackerLinkEditSheet(
            seriesId: seriesId,
            seriesTitle: seriesTitle,
            alternateTitles: alternateTitles,
            link: link
          ) {
            await load()
          }
        }
      }
    #endif
  }

  private func load() async {
    guard !AppConfig.isOffline else { return }
    do {
      let loadedLinks = try await TrackerService.getLinks(seriesId: seriesId)
      guard !Task.isCancelled else { return }
      if links != loadedLinks {
        withAnimation(.appCurve()) {
          links = loadedLinks
        }
      }
      for link in loadedLinks {
        do {
          let state = try await TrackerService.getState(
            provider: link.provider, trackId: link.trackId)
          guard !Task.isCancelled else { return }
          withAnimation(.appCurve()) {
            states[link.provider] = state
            providersRequiringLogin.remove(link.provider)
          }
        } catch APIError.unauthorized {
          _ = withAnimation(.appCurve()) {
            providersRequiringLogin.insert(link.provider)
          }
        } catch {}
      }
    } catch {}
  }
}
