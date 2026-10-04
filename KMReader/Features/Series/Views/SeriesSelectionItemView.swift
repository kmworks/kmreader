//
// SeriesSelectionItemView.swift
//
//

import SwiftUI

/// View for series selection mode that accepts only seriesId and fetches a series display projection.
struct SeriesSelectionItemView: View {
  let seriesId: String
  let layout: BrowseLayoutMode
  @Binding var selectedSeriesIds: Set<String>

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var item: SeriesDisplayItem?

  init(
    seriesId: String,
    layout: BrowseLayoutMode,
    selectedSeriesIds: Binding<Set<String>>
  ) {
    self.seriesId = seriesId
    self.layout = layout
    self._selectedSeriesIds = selectedSeriesIds

  }

  private var isSelected: Bool {
    selectedSeriesIds.contains(seriesId)
  }

  var body: some View {
    selectionBody
      .allowsHitTesting(false)
      .animation(.appCurve(), value: isSelected)
      .contentShape(Rectangle())
      .highPriorityGesture(
        TapGesture().onEnded {
          if isSelected {
            selectedSeriesIds.remove(seriesId)
          } else {
            selectedSeriesIds.insert(seriesId)
          }
        }
      )
      .task(id: "\(current.instanceId)|\(seriesId)") {
        await loadItem()
      }
      .onReceive(NotificationCenter.default.publisher(for: .seriesProjectionDidChange)) {
        notification in
        guard shouldReload(for: notification) else { return }
        reloadItem()
      }
  }

  @ViewBuilder
  private var selectionBody: some View {
    switch layout {
    case .grid, .largeGrid:
      selectionContent
        .selectionDimmed(!isSelected, scale: 0.92)
    case .list:
      HStack(spacing: 12) {
        selectionContent
          .selectionDimmed(!isSelected, scale: 0.97)
        SelectionBadge(isSelected: isSelected)
      }
    }
  }

  @ViewBuilder
  private var selectionContent: some View {
    if let item {
      switch layout {
      case .grid, .largeGrid:
        SeriesCardView(
          item: item,
          showUnreadIndicator: false,
          selectionIsSelected: isSelected
        )
      case .list:
        SeriesRowView(
          item: item
        )
      }
    } else {
      CardPlaceholder(layout: layout, kind: .series)
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

  private func loadItem() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      return
    }
    item = try? await database.fetchSeriesDisplayItem(
      seriesId: seriesId,
      instanceId: current.instanceId
    )
  }
}
