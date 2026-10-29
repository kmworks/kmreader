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
  @State private var unlinkingLink: TrackerLink?
  @State private var showUnlinkConfirmation = false

  var body: some View {
    List {
      Section {
        Picker(String(localized: "Provider"), selection: $provider) {
          Text(filterLabel(String(localized: "All"), count: counts?.series))
            .tag(TrackerProvider?.none)
          ForEach(TrackerProvider.allCases, id: \.self) { provider in
            Text(filterLabel(provider.displayName, count: counts?.providers[provider.rawValue]))
              .tag(TrackerProvider?.some(provider))
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
            TrackerBindingRow(group: group) { link in
              unlinkingLink = link
              showUnlinkConfirmation = true
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
    .alert(
      String(localized: "Unlink Tracker"),
      isPresented: $showUnlinkConfirmation,
      presenting: unlinkingLink
    ) { link in
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Unlink"), role: .destructive) { unlink(link) }
    } message: { _ in
      Text(String(localized: "This removes the series binding but does not change the remote entry."))
    }
  }

  private func unlink(_ link: TrackerLink) {
    Task {
      do {
        try await TrackerService.deleteLink(seriesId: link.seriesId, provider: link.provider)
        ErrorManager.shared.notify(message: String(localized: "Tracker unlinked."))
        loadTask?.cancel()
        await load(refresh: true)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func filterLabel(_ name: String, count: Int?) -> String {
    guard let count else { return name }
    return "\(name) (\(count))"
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
