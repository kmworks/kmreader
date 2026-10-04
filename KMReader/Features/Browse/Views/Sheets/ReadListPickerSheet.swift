//
// ReadListPickerSheet.swift
//
//

import SwiftUI

struct ReadListPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var isLoading = false
  @State private var readLists: [ReadListDisplayItem] = []

  let bookId: String
  let onSelect: (String) -> Void

  init(
    bookId: String,
    onSelect: @escaping (String) -> Void
  ) {
    self.bookId = bookId
    self.onSelect = onSelect
  }

  private var pickerItems: [EntityPickerItem] {
    readLists.map { readList in
      EntityPickerItem(
        id: readList.readListId,
        name: readList.name,
        alreadyIn: readList.bookIds.contains(bookId)
      )
    }
  }

  var body: some View {
    EntityPickerSheet(
      title: String(localized: "Select Read List"),
      emptyText: String(localized: "No read lists found"),
      icon: ContentIcon.readList,
      items: pickerItems,
      isLoading: isLoading,
      onSelect: onSelect
    ) {
      CreateReadListSheet(
        bookId: bookId,
        onCreate: { _ in
          dismiss()
        }
      )
    }
    .task {
      await refreshReadLists()
    }
  }

  private func refreshReadLists() async {
    await loadReadLists()
    guard !AppConfig.isOffline else { return }
    withAnimation {
      isLoading = true
    }
    await SyncService.syncReadLists(instanceId: current.instanceId)
    withAnimation {
      isLoading = false
    }
    await loadReadLists()
  }

  private func loadReadLists() async {
    guard !current.instanceId.isEmpty else {
      if !readLists.isEmpty {
        withAnimation {
          readLists = []
        }
      }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedReadLists = try await database.fetchReadListDisplayItems(
        instanceId: current.instanceId
      )
      if readLists != loadedReadLists {
        withAnimation {
          readLists = loadedReadLists
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
