//
// LibraryEditSheet.swift
//
//

import SwiftUI

struct LibraryEditSheet: View {
  let library: Library
  @Environment(\.dismiss) private var dismiss
  @State private var libraryUpdate: LibraryUpdate
  @State private var isSaving = false
  @State private var showDirectoryBrowser = false

  init(library: Library) {
    self.library = library
    _libraryUpdate = State(initialValue: LibraryUpdate.from(library))
  }

  private var isValid: Bool {
    !libraryUpdate.name.isEmpty && !libraryUpdate.root.isEmpty
  }

  var body: some View {
    SheetView(
      title: String(localized: "library.edit.title", defaultValue: "Edit Library"),
      size: .large,
      applyFormStyle: true
    ) {
      Form {
        LibraryFormSections(fields: $libraryUpdate, showDirectoryBrowser: $showDirectoryBrowser)
      }
    } controls: {
      Button(action: saveLibrary) {
        if isSaving {
          LoadingIcon()
        } else {
          Label(String(localized: "Save"), systemImage: AppIcon.confirm)
        }
      }
      .disabled(isSaving || !isValid)
    }
    .sheet(isPresented: $showDirectoryBrowser) {
      DirectoryBrowserSheet(selectedPath: $libraryUpdate.root)
    }
  }

  private func saveLibrary() {
    isSaving = true
    Task {
      do {
        try await LibraryService.updateLibrary(id: library.id, update: libraryUpdate)
        await LibraryManager.shared.refreshLibraries()
        ErrorManager.shared.notify(
          message: String(
            localized: "notification.library.updated", defaultValue: "Library updated")
        )
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSaving = false
    }
  }
}
