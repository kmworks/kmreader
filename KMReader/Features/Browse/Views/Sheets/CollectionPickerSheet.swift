//
// CollectionPickerSheet.swift
//
//

import SwiftUI

private struct CollectionItem: Identifiable {
  let id: String
  let name: String
  let alreadyIn: Bool
}

struct CollectionPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var selectedCollectionId: String?
  @State private var isLoading = false
  @State private var searchText: String = ""
  @State private var showCreateSheet = false
  @State private var isCreating = false
  @State private var collections: [CollectionDisplayItem] = []

  let seriesId: String
  let onSelect: (String) -> Void

  init(
    seriesId: String,
    onSelect: @escaping (String) -> Void
  ) {
    self.seriesId = seriesId
    self.onSelect = onSelect
  }

  private var filteredCollections: [CollectionDisplayItem] {
    if searchText.isEmpty {
      return collections
    }
    return collections.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var collectionItems: [CollectionItem] {
    filteredCollections.map { collection in
      CollectionItem(
        id: collection.collectionId,
        name: collection.name,
        alreadyIn: collection.seriesIds.contains(seriesId)
      )
    }
  }

  var body: some View {
    SheetView(title: String(localized: "Select Collection"), size: .large, applyFormStyle: true) {
      Form {
        if isLoading && collections.isEmpty {
          LoadingIcon()
            .frame(maxWidth: .infinity)
        } else if collections.isEmpty {
          Text("No collections found")
            .foregroundColor(.secondary)
        } else if filteredCollections.isEmpty {
          ContentUnavailableView.search(text: searchText)
        } else {
          Section {
            ForEach(collectionItems) { item in
              Button {
                if !item.alreadyIn {
                  selectedCollectionId = item.id
                }
              } label: {
                HStack {
                  Label(item.name, systemImage: ContentIcon.collection)
                  Spacer()
                  if item.alreadyIn {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                  } else if selectedCollectionId == item.id {
                    Image(systemName: "checkmark")
                      .foregroundStyle(.tint)
                  }
                }
                .foregroundStyle(item.alreadyIn ? .secondary : .primary)
                .animation(.appCurve(), value: selectedCollectionId == item.id)
              }
              .disabled(item.alreadyIn)
            }
          }
        }
      }
    } controls: {
      Button {
        withAnimation {
          showCreateSheet = true
        }
      } label: {
        Label("Create New", systemImage: "plus.circle.fill")
      }
      .disabled(!current.isAdmin)

      HStack(spacing: 12) {
        Button(action: confirmSelection) {
          Label("Done", systemImage: "checkmark")
        }
        .disabled(selectedCollectionId == nil)
      }
    }
    .searchable(text: $searchText)
    .task {
      await refreshCollections()
    }
    .sheet(isPresented: $showCreateSheet) {
      CreateCollectionSheet(
        isCreating: $isCreating,
        seriesId: seriesId,
        onCreate: { _ in
          dismiss()
        }
      )
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

  private func confirmSelection() {
    if let selectedCollectionId = selectedCollectionId {
      onSelect(selectedCollectionId)
      dismiss()
    }
  }
}

struct CreateCollectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var isCreating: Bool
  let seriesId: String
  let onCreate: (String) -> Void

  @State private var name: String = ""

  var body: some View {
    SheetView(title: String(localized: "Create Collection"), size: .medium, applyFormStyle: true) {
      Form {
        Section {
          TextField("Collection Name", text: $name)
        }
      }
    } controls: {
      Button(action: createCollection) {
        if isCreating {
          LoadingIcon()
        } else {
          Label("Create", systemImage: "checkmark")
        }
      }
      .disabled(name.isEmpty || isCreating)
    }
  }

  private func createCollection() {
    guard !name.isEmpty else { return }

    withAnimation {
      isCreating = true
    }

    Task {
      do {
        let collection = try await CollectionService.createCollection(
          name: name,
          seriesIds: [seriesId]
        )
        // Sync the collection to update its local series IDs
        _ = try? await SyncService.syncCollection(id: collection.id)
        ErrorManager.shared.notify(message: String(localized: "notification.collection.created"))
        withAnimation {
          isCreating = false
        }
        onCreate(collection.id)
        dismiss()
      } catch {
        withAnimation {
          isCreating = false
        }
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
