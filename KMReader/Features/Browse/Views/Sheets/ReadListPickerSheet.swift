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

  let bookIds: [String]
  let onSelect: (String) -> Void
  /// Create-New completion: the new list already holds the given books, so
  /// callers only need to react to the dismissal (e.g. exit selection mode).
  var onCreate: ((String) -> Void)? = nil

  init(
    bookIds: [String],
    onSelect: @escaping (String) -> Void,
    onCreate: ((String) -> Void)? = nil
  ) {
    self.bookIds = bookIds
    self.onSelect = onSelect
    self.onCreate = onCreate
  }

  private var pickerItems: [EntityPickerItem] {
    readLists.map { readList in
      EntityPickerItem(
        id: readList.readListId,
        name: readList.name,
        alreadyIn: bookIds.allSatisfy(readList.bookIds.contains)
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
        bookIds: bookIds,
        onCreate: { id in
          onCreate?(id)
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
