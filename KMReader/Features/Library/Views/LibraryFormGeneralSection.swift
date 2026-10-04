//
// LibraryFormGeneralSection.swift
//
//

import SwiftUI

/// General section of the library add/edit form: name and root folder.
struct LibraryFormGeneralSection<Fields: LibraryFormFields>: View {
  @Binding var fields: Fields
  @Binding var showDirectoryBrowser: Bool

  var body: some View {
    Section(header: Text(String(localized: "library.add.section.general", defaultValue: "General"))) {
      TextField(
        String(localized: "library.add.field.name", defaultValue: "Name"),
        text: $fields.name
      )

      HStack {
        TextField(
          String(localized: "library.add.field.root", defaultValue: "Root Folder"),
          text: $fields.root
        )
        #if os(iOS) || os(macOS)
          Button {
            showDirectoryBrowser = true
          } label: {
            Image(systemName: "folder")
          }
        #endif
      }
    }
  }
}
