//
// ReadListPickerSheet.swift
//
//

import SwiftUI

private struct ReadListItem: Identifiable {
  let id: String
  let name: String
  let alreadyIn: Bool
}

struct ReadListPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var selectedReadListId: String?
  @State private var isLoading = false
  @State private var searchText: String = ""
  @State private var showCreateSheet = false
  @State private var isCreating = false
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

  private var filteredReadLists: [ReadListDisplayItem] {
    if searchText.isEmpty {
      return readLists
    }
    return readLists.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var readListItems: [ReadListItem] {
    filteredReadLists.map { readList in
      ReadListItem(
        id: readList.readListId,
        name: readList.name,
        alreadyIn: readList.bookIds.contains(bookId)
      )
    }
  }

  var body: some View {
    SheetView(title: String(localized: "Select Read List"), size: .large, applyFormStyle: true) {
      Form {
        if isLoading && readLists.isEmpty {
          LoadingIcon()
            .frame(maxWidth: .infinity)
        } else if readLists.isEmpty {
          Text("No read lists found")
            .foregroundColor(.secondary)
        } else if filteredReadLists.isEmpty {
          ContentUnavailableView.search(text: searchText)
        } else {
          Section {
            ForEach(readListItems) { item in
              Button {
                if !item.alreadyIn {
                  selectedReadListId = item.id
                }
              } label: {
                HStack {
                  Label(item.name, systemImage: ContentIcon.readList)
                  Spacer()
                  if item.alreadyIn {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                  } else if selectedReadListId == item.id {
                    Image(systemName: "checkmark")
                      .foregroundStyle(.tint)
                  }
                }
                .foregroundStyle(item.alreadyIn ? .secondary : .primary)
                .animation(.appCurve(), value: selectedReadListId == item.id)
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
        .disabled(selectedReadListId == nil)
      }
    }
    .searchable(text: $searchText)
    .task {
      await refreshReadLists()
    }
    .sheet(isPresented: $showCreateSheet) {
      CreateReadListSheet(
        isCreating: $isCreating,
        bookId: bookId,
        onCreate: { _ in
          dismiss()
        }
      )
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

  private func confirmSelection() {
    if let selectedReadListId = selectedReadListId {
      onSelect(selectedReadListId)
      dismiss()
    }
  }
}

struct CreateReadListSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var isCreating: Bool
  let bookId: String
  let onCreate: (String) -> Void

  @State private var name: String = ""
  @State private var summary: String = ""

  var body: some View {
    SheetView(title: String(localized: "Create Read List"), size: .medium, applyFormStyle: true) {
      Form {
        Section {
          TextField("Read List Name", text: $name)
          TextField("Summary (Optional)", text: $summary, axis: .vertical)
            .lineLimit(3...6)
        }
      }
    } controls: {
      Button(action: createReadList) {
        if isCreating {
          LoadingIcon()
        } else {
          Label("Create", systemImage: "checkmark")
        }
      }
      .disabled(name.isEmpty || isCreating)
    }
  }

  private func createReadList() {
    guard !name.isEmpty else { return }

    withAnimation {
      isCreating = true
    }

    Task {
      do {
        let readList = try await ReadListService.createReadList(
          name: name,
          summary: summary,
          bookIds: [bookId]
        )
        // Sync the readlist to update its local book IDs
        _ = try? await SyncService.syncReadList(id: readList.id)
        ErrorManager.shared.notify(message: String(localized: "notification.readList.created"))
        withAnimation {
          isCreating = false
        }
        onCreate(readList.id)
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
