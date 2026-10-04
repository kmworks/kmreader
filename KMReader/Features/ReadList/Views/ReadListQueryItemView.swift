//
// ReadListQueryItemView.swift
//
//

import SwiftUI

/// Wrapper view that accepts only readListId and fetches a read-list display projection.
struct ReadListQueryItemView: View {
  let readListId: String
  var layout: BrowseLayoutMode = .grid
  var onItemMissing: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var item: ReadListDisplayItem?
  @State private var showDeleteConfirmation = false

  init(
    readListId: String,
    layout: BrowseLayoutMode = .grid,
    onItemMissing: (() -> Void)? = nil
  ) {
    self.readListId = readListId
    self.layout = layout
    self.onItemMissing = onItemMissing

  }

  var body: some View {
    Group {
      if let item {
        switch layout {
        case .grid, .largeGrid:
          ReadListCardView(
            item: item,
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            },
            cardWidth: layout.cardWidth
          )
        case .list:
          ReadListRowView(
            item: item,
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            }
          )
        }
      } else {
        CardPlaceholder(layout: layout, kind: .readList)
      }
    }
    .task(id: "\(current.instanceId)|\(readListId)") {
      await loadItem()
    }
    .onReceive(NotificationCenter.default.publisher(for: .readListProjectionDidChange)) {
      notification in
      guard shouldReload(for: notification) else { return }
      reloadItem()
    }
    .alert("Delete Read List", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteReadList()
      }
    } message: {
      Text("Are you sure you want to delete this read list? This action cannot be undone.")
    }
  }

  private func shouldReload(for notification: Notification) -> Bool {
    let changedIds = changedReadListIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    return changedIds.contains(readListId)
  }

  private func changedReadListIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["readListIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["readListIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["readListId"] as? String {
      return [id]
    }
    return []
  }

  private func reloadItem() {
    Task {
      await loadItem()
    }
  }

  private func deleteReadList() {
    Task {
      do {
        try await ReadListService.deleteReadList(readListId: readListId)
        ErrorManager.shared.notify(message: String(localized: "notification.readList.deleted"))
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
    let loadedItem = try? await database.fetchReadListDisplayItem(
      readListId: readListId,
      instanceId: current.instanceId
    )
    item = loadedItem
    if loadedItem == nil {
      onItemMissing?()
    }
  }
}
