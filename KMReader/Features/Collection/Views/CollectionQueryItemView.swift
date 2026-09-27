//
// CollectionQueryItemView.swift
//
//

import SwiftUI

/// Wrapper view that accepts only collectionId and fetches a collection display projection.
struct CollectionQueryItemView: View {
  let collectionId: String
  var layout: BrowseLayoutMode = .grid
  var onItemMissing: (() -> Void)? = nil

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var item: CollectionDisplayItem?
  @State private var showDeleteConfirmation = false

  init(
    collectionId: String,
    layout: BrowseLayoutMode = .grid,
    onItemMissing: (() -> Void)? = nil
  ) {
    self.collectionId = collectionId
    self.layout = layout
    self.onItemMissing = onItemMissing

  }

  var body: some View {
    Group {
      if let item {
        switch layout {
        case .grid, .largeGrid:
          CollectionCardView(
            item: item,
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            }
          )
        case .list:
          CollectionRowView(
            item: item,
            onMutationCompleted: reloadItem,
            onDeleteRequested: {
              showDeleteConfirmation = true
            }
          )
        }
      } else {
        CardPlaceholder(layout: layout, kind: .collection)
      }
    }
    .task(id: "\(current.instanceId)|\(collectionId)") {
      await loadItem()
    }
    .onReceive(NotificationCenter.default.publisher(for: .collectionProjectionDidChange)) {
      notification in
      guard shouldReload(for: notification) else { return }
      reloadItem()
    }
    .alert("Delete Collection", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteCollection()
      }
    } message: {
      Text("Are you sure you want to delete this collection? This action cannot be undone.")
    }
  }

  private func shouldReload(for notification: Notification) -> Bool {
    let changedIds = changedCollectionIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    return changedIds.contains(collectionId)
  }

  private func changedCollectionIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["collectionIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["collectionIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["collectionId"] as? String {
      return [id]
    }
    return []
  }

  private func reloadItem() {
    Task {
      await loadItem()
    }
  }

  private func deleteCollection() {
    Task {
      do {
        try await CollectionService.deleteCollection(collectionId: collectionId)
        ErrorManager.shared.notify(message: String(localized: "notification.collection.deleted"))
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
    let loadedItem = try? await database.fetchCollectionDisplayItem(
      collectionId: collectionId,
      instanceId: current.instanceId
    )
    item = loadedItem
    if loadedItem == nil {
      onItemMissing?()
    }
  }
}
