//
// LibraryFormOptionsSection.swift
//
//

import SwiftUI

/// Options section of the library add/edit form: analysis, file management,
/// and series cover mode.
struct LibraryFormOptionsSection<Fields: LibraryFormFields>: View {
  @Binding var fields: Fields

  var body: some View {
    Section(header: Text(String(localized: "library.add.section.options", defaultValue: "Options"))) {
      Group {
        Text(String(localized: "library.add.subsection.analysis", defaultValue: "Analysis"))
          .font(.subheadline)
          .foregroundColor(.secondary)

        Toggle(
          String(localized: "library.add.field.hashFiles", defaultValue: "Hash files"),
          isOn: $fields.hashFiles
        )

        Toggle(
          String(localized: "library.add.field.hashPages", defaultValue: "Hash pages"),
          isOn: $fields.hashPages
        )

        Toggle(
          String(localized: "library.add.field.hashKoreader", defaultValue: "Hash KOReader"),
          isOn: $fields.hashKoreader
        )

        Toggle(
          String(
            localized: "library.add.field.analyzeDimensions", defaultValue: "Analyze dimensions"),
          isOn: $fields.analyzeDimensions
        )
      }

      Group {
        Text(
          String(
            localized: "library.add.subsection.fileManagement", defaultValue: "File Management")
        )
        .font(.subheadline)
        .foregroundColor(.secondary)

        Toggle(
          String(
            localized: "library.add.field.repairExtensions", defaultValue: "Repair extensions"),
          isOn: $fields.repairExtensions
        )

        Toggle(
          String(localized: "library.add.field.convertToCbz", defaultValue: "Convert to CBZ"),
          isOn: $fields.convertToCbz
        )
      }

      Picker(
        String(localized: "library.add.field.seriesCover", defaultValue: "Series cover"),
        selection: $fields.seriesCover
      ) {
        ForEach(SeriesCoverMode.allCases) { mode in
          Text(mode.localizedName).tag(mode)
        }
      }
    }
  }
}
