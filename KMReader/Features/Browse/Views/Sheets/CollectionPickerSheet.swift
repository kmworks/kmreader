//
// CollectionPickerSheet.swift
//
//

import SwiftUI

struct CollectionPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var isLoading = false
  @State private var collections: [CollectionDisplayItem] = []

  let seriesIds: [String]
  let onSelect: (String) -> Void

  init(
    seriesIds: [String],
    onSelect: @escaping (String) -> Void
  ) {
    self.seriesIds = seriesIds
    self.onSelect = onSelect
  }

  private var pickerItems: [EntityPickerItem] {
    collections.map { collection in
      EntityPickerItem(
        id: collection.collectionId,
        name: collection.name,
        alreadyIn: seriesIds.allSatisfy(collection.seriesIds.contains)
      )
    }
  }

  var body: some View {
    EntityPickerSheet(
      title: String(localized: "Select Collection"),
      emptyText: String(localized: "No collections found"),
      icon: ContentIcon.collection,
      items: pickerItems,
      isLoading: isLoading,
      onSelect: onSelect
    ) {
      CreateCollectionSheet(
        seriesIds: seriesIds,
        onCreate: { _ in
          dismiss()
        }
      )
    }
    .task {
      await refreshCollections()
    }
  }

  private func refreshCollections() async {
    await loadCollections()
    guard !AppConfig.isOffline else { return }
    withAnimation {
      isLoading = true
    }
    await SyncService.syncCollections(instanceId: current.instanceId)
    withAnimation {
      isLoading = false
    }
    await loadCollections()
  }

  private func loadCollections() async {
    guard !current.instanceId.isEmpty else {
      if !collections.isEmpty {
        withAnimation {
          collections = []
        }
      }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedCollections = try await database.fetchCollectionDisplayItems(
        instanceId: current.instanceId
      )
      if collections != loadedCollections {
        withAnimation {
          collections = loadedCollections
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
