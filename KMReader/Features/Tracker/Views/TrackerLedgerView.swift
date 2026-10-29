//
// TrackerLedgerView.swift
//

import SwiftUI

struct TrackerLedgerView: View {
  @State private var pagination = PaginationState<TrackerLedgerItem>(pageSize: 20)
  @State private var isLoading = false

  var body: some View {
    List {
      if pagination.isEmpty && !isLoading {
        Section {
          ContentUnavailableView {
            Label(String(localized: "No Manual Updates"), systemImage: "clock.arrow.circlepath")
          } description: {
            Text(String(localized: "Tracker entries updated manually will appear here."))
          }
        }
      } else {
        Section {
          ForEach(pagination.items) { item in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(item.provider.displayName)
                Spacer()
                Text(item.updatedDate.formatted(.relative(presentation: .named)))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              if let url = item.url.flatMap(URL.init(string:)) {
                Link(item.title ?? item.trackId, destination: url)
              } else {
                Text(item.title ?? item.trackId)
              }
            }
            .onAppear { loadMoreIfNeeded(item) }
          }
          if isLoading {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          }
        }
      }
    }
    .platformNavigationTitle(String(localized: "Recent Manual Updates"))
    .task { await load(refresh: true) }
    .refreshable { await load(refresh: true) }
  }

  private func load(refresh: Bool) async {
    if refresh { pagination.reset() }
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let page = try await TrackerService.getLedger(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      _ = pagination.applyPage(page.content)
      pagination.advance(moreAvailable: !page.last)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadMoreIfNeeded(_ item: TrackerLedgerItem) {
    guard pagination.shouldLoadMore(after: item), !isLoading else { return }
    Task { await load(refresh: false) }
  }
}
