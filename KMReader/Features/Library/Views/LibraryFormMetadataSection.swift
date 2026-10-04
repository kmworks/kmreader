//
// LibraryFormMetadataSection.swift
//
//

import SwiftUI

/// Metadata section of the library add/edit form: ComicInfo, EPUB, and other
/// import toggles.
struct LibraryFormMetadataSection<Fields: LibraryFormFields>: View {
  @Binding var fields: Fields

  var body: some View {
    Section(
      header: Text(String(localized: "library.add.section.metadata", defaultValue: "Metadata"))
    ) {
      Group {
        Text(String(localized: "library.add.subsection.comicinfo", defaultValue: "ComicInfo"))
          .font(.subheadline)
          .foregroundColor(.secondary)

        Toggle(
          String(
            localized: "library.add.field.importComicInfoBook", defaultValue: "Import book metadata"
          ),
          isOn: $fields.importComicInfoBook
        )

        Toggle(
          String(
            localized: "library.add.field.importComicInfoSeries",
            defaultValue: "Import series metadata"),
          isOn: $fields.importComicInfoSeries
        )

        Toggle(
          String(
            localized: "library.add.field.importComicInfoSeriesAppendVolume",
            defaultValue: "Append volume to series"),
          isOn: $fields.importComicInfoSeriesAppendVolume
        )

        Toggle(
          String(
            localized: "library.add.field.importComicInfoCollection",
            defaultValue: "Import collections"),
          isOn: $fields.importComicInfoCollection
        )

        Toggle(
          String(
            localized: "library.add.field.importComicInfoReadList",
            defaultValue: "Import read lists"),
          isOn: $fields.importComicInfoReadList
        )
      }

      Group {
        Text(String(localized: "library.add.subsection.epub", defaultValue: "EPUB"))
          .font(.subheadline)
          .foregroundColor(.secondary)

        Toggle(
          String(
            localized: "library.add.field.importEpubBook", defaultValue: "Import book metadata"),
          isOn: $fields.importEpubBook
        )

        Toggle(
          String(
            localized: "library.add.field.importEpubSeries", defaultValue: "Import series metadata"),
          isOn: $fields.importEpubSeries
        )
      }

      Group {
        Text(String(localized: "library.add.subsection.other", defaultValue: "Other"))
          .font(.subheadline)
          .foregroundColor(.secondary)

        Toggle(
          String(
            localized: "library.add.field.importMylarSeries", defaultValue: "Import Mylar series"),
          isOn: $fields.importMylarSeries
        )

        Toggle(
          String(
            localized: "library.add.field.importLocalArtwork", defaultValue: "Import local artwork"),
          isOn: $fields.importLocalArtwork
        )

        Toggle(
          String(
            localized: "library.add.field.importBarcodeIsbn", defaultValue: "Import barcode ISBN"),
          isOn: $fields.importBarcodeIsbn
        )
      }
    }
  }
}
