//
// TrackerBindingsView.swift
//

import SwiftUI

struct TrackerBindingsView: View {
  @State private var pagination = PaginationState<TrackerLinkGroup>(pageSize: 20)
  @State private var provider: TrackerProvider?
  @State private var counts: TrackerLinkCounts?
  @State private var isLoading = false
  @State private var loadTask: Task<Void, Never>?

  var body: some View {
    List {
      Section {
        Picker(String(localized: "Provider"), selection: $provider) {
          Text(String(localized: "All")).tag(TrackerProvider?.none)
          ForEach(TrackerProvider.allCases, id: \.self) { provider in
            Text(provider.displayName).tag(TrackerProvider?.some(provider))
          }
        }
        .onChange(of: provider) { _, _ in
          loadTask?.cancel()
          loadTask = Task { await load(refresh: true) }
        }
      }
      if pagination.isEmpty && !isLoading {
        Section {
          ContentUnavailableView {
            Label(String(localized: "No Linked Series"), systemImage: "link")
          } description: {
            Text(String(localized: "Link a series from its detail page to sync reading progress."))
          }
        }
      } else {
        Section {
          ForEach(pagination.items) { group in
            VStack(alignment: .leading, spacing: 8) {
              SeriesQueryItemView(seriesId: group.seriesId, layout: .list)
              ForEach(group.links) { link in
                if let url = link.provider.entryURL(trackId: link.trackId) {
                  Link(destination: url) {
                    HStack {
                      Text(link.provider.displayName)
                      Spacer()
                      Text(link.displayTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                  }
                }
              }
            }
            .onAppear { loadMoreIfNeeded(group) }
          }
          if isLoading {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          }
        } footer: {
          if let counts {
            Text(String.localizedStringWithFormat(String(localized: "%d linked series"), counts.series))
          }
        }
      }
    }
    .platformNavigationTitle(String(localized: "Linked Series"))
    .task {
      loadTask?.cancel()
      await load(refresh: true)
    }
    .onDisappear {
      loadTask?.cancel()
    }
    .refreshable {
      await load(refresh: true)
    }
  }

  private func load(refresh: Bool) async {
    if refresh { pagination.reset() }
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let response = try await TrackerService.getLinks(
        page: pagination.currentPage,
        size: pagination.pageSize,
        provider: provider
      )
      counts = response.counts
      guard !Task.isCancelled else { return }
      _ = pagination.applyPage(response.page.content)
      pagination.advance(moreAvailable: !response.page.last)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadMoreIfNeeded(_ group: TrackerLinkGroup) {
    guard pagination.shouldLoadMore(after: group), !isLoading else { return }
    Task { await load(refresh: false) }
  }
}
