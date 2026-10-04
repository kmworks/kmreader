//
// LibraryAddSheet.swift
//
//

import SwiftUI

struct LibraryAddSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var libraryCreation = LibraryCreation.createDefault()
  @State private var isCreating = false
  @State private var showDirectoryBrowser = false

  private var isValid: Bool {
    !libraryCreation.name.isEmpty && !libraryCreation.root.isEmpty
  }

  var body: some View {
    SheetView(
      title: String(localized: "library.add.title", defaultValue: "Add Library"),
      size: .large,
      applyFormStyle: true
    ) {
      Form {
        LibraryFormSections(fields: $libraryCreation, showDirectoryBrowser: $showDirectoryBrowser)
      }
    } controls: {
      Button(action: createLibrary) {
        if isCreating {
          LoadingIcon()
        } else {
          Label(String(localized: "Create"), systemImage: "plus")
        }
      }
      .disabled(isCreating || !isValid)
    }
    .sheet(isPresented: $showDirectoryBrowser) {
      DirectoryBrowserSheet(selectedPath: $libraryCreation.root)
    }
  }

  private func createLibrary() {
    isCreating = true
    Task {
      do {
        _ = try await LibraryService.createLibrary(libraryCreation)
        await LibraryManager.shared.refreshLibraries()
        ErrorManager.shared.notify(
          message: String(
            localized: "notification.library.created", defaultValue: "Library created")
        )
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isCreating = false
    }
  }
}
