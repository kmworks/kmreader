//
// SeriesQueryItemView.swift
//
//

import SwiftUI

/// Wrapper view that accepts only seriesId and fetches a series display projection.
struct SeriesQueryItemView: View {
  let seriesId: String
  let layout: BrowseLayoutMode
  var coverOnly: Bool = false
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth
  var onItemMissing: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var item: SeriesDisplayItem?
  @State private var showDeleteConfirmation = false

  init(
    seriesId: String,
    layout: BrowseLayoutMode,
    coverOnly: Bool = false,
    cardWidth: CGFloat = LayoutConfig.gridCardWidth,
    onItemMissing: (() -> Void)? = nil
  ) {
    self.seriesId = seriesId
    self.layout = layout
    self.coverOnly = coverOnly
    self.cardWidth = cardWidth
    self.onItemMissing = onItemMissing

  }

  var body: some View {
    Group {
      if let item {
        switch layout {
        case .grid, .largeGrid:
          SeriesCardView(
            item: item,
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            },
            coverOnly: coverOnly,
            cardWidth: cardWidth
          )
        case .list:
          SeriesRowView(
            item: item,
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            }
          )
        }
      } else {
        CardPlaceholder(layout: layout, kind: .series, cardWidth: cardWidth, coverOnly: coverOnly)
      }
    }
    .task(id: "\(current.instanceId)|\(seriesId)") {
      await loadItem()
    }
    .onReceive(NotificationCenter.default.publisher(for: .seriesProjectionDidChange)) {
      notification in
      guard shouldReload(for: notification) else { return }
      reloadItem()
    }
    .alert("Delete Series", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteSeries()
      }
    } message: {
      Text("Are you sure you want to delete this series? This action cannot be undone.")
    }
  }

  private func shouldReload(for notification: Notification) -> Bool {
    let changedIds = changedSeriesIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    return changedIds.contains(seriesId)
  }

  private func changedSeriesIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["seriesIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["seriesIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["seriesId"] as? String {
      return [id]
    }
    return []
  }

  private func reloadItem() {
    Task {
      await loadItem()
    }
  }

  private func deleteSeries() {
    Task {
      do {
        if let item {
          try await SeriesDeletionService.deleteSeries(item)
        } else {
          try await SeriesDeletionService.deleteSeries(seriesId: seriesId, instanceId: current.instanceId)
        }
        ErrorManager.shared.notify(message: String(localized: "notification.series.deleted"))
        await loadItem()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func loadItem() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      return
    }
    let loadedItem = try? await database.fetchSeriesDisplayItem(
      seriesId: seriesId,
      instanceId: current.instanceId
    )
    item = loadedItem
    if loadedItem == nil {
      onItemMissing?()
    }
  }
}
