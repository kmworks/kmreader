//
// ServerLibrariesView.swift
//
//

import SwiftUI

struct ServerLibrariesView: View {
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var libraryPendingDelete: LibrarySelection?
  @State private var deleteConfirmationText: String = ""
  @State private var showAddSheet = false
  @State private var libraryToEdit: Library?
  @State private var libraryListRefreshTrigger = 0

  private var isDeleteAlertPresented: Binding<Bool> {
    Binding(
      get: { libraryPendingDelete != nil },
      set: {
        if !$0 {
          libraryPendingDelete = nil
          deleteConfirmationText = ""
        }
      }
    )
  }

  private var isEditSheetPresented: Binding<Bool> {
    Binding(
      get: { libraryToEdit != nil },
      set: { if !$0 { libraryToEdit = nil } }
    )
  }

  var body: some View {
    LibraryListContent(
      selectionEnabled: false,
      alwaysRefreshMetrics: true,
      forceMetricsOnAppear: true,
      onEditLibrary: { libraryId in
        fetchAndEditLibrary(libraryId)
      },
      onDeleteLibrary: { library in
        libraryPendingDelete = library
        deleteConfirmationText = ""
      },
      refreshTrigger: libraryListRefreshTrigger
    )
    .platformNavigationTitle(ServerSection.libraries.title)
    .toolbar {
      if current.isAdmin && !isOffline {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showAddSheet = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    }
    .sheet(isPresented: $showAddSheet, onDismiss: refreshLibraryList) {
      LibraryAddSheet()
    }
    .sheet(isPresented: isEditSheetPresented, onDismiss: refreshLibraryList) {
      if let library = libraryToEdit {
        LibraryEditSheet(library: library)
      }
    }
    .alert(String(localized: "settings.libraries.alert.title"), isPresented: isDeleteAlertPresented) {
      if let libraryPendingDelete {
        TextField(
          String(localized: "settings.libraries.alert.placeholder"),
          text: $deleteConfirmationText)
        Button(String(localized: "settings.libraries.alert.delete"), role: .destructive) {
          deleteConfirmedLibrary(libraryPendingDelete)
        }
        .disabled(deleteConfirmationText != libraryPendingDelete.name)
        Button(String(localized: "Cancel"), role: .cancel) {
          deleteConfirmationText = ""
        }
      }
    } message: {
      if let libraryPendingDelete {
        Text(
          deleteLibraryConfirmationMessage(for: libraryPendingDelete)
        )
      }
    }
  }

  private func fetchAndEditLibrary(_ libraryId: String) {
    Task {
      do {
        let library = try await LibraryService.getLibrary(id: libraryId)
        libraryToEdit = library
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deleteConfirmedLibrary(_ library: LibrarySelection) {
    Task {
      do {
        try await LibraryService.deleteLibrary(id: library.libraryId)
        await LibraryManager.shared.refreshLibraries()
        refreshLibraryList()
        ErrorManager.shared.notify(
          message: String(localized: "notification.library.deleted"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      libraryPendingDelete = nil
      deleteConfirmationText = ""
    }
  }

  private func refreshLibraryList() {
    libraryListRefreshTrigger += 1
  }
}

private func deleteLibraryConfirmationMessage(for library: LibrarySelection) -> String {
  let format = String(
    localized: "settings.libraries.alert.message",
    defaultValue:
      "This will permanently delete %1$@ from Komga.\n\nTo confirm, please type the library name: %2$@"
  )
  return String(format: format, locale: Locale.current, library.name, library.name)
}
