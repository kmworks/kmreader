//
// BookMediaInfoSection.swift
//
//

import SwiftUI

/// Media Information section of book/oneshot detail pages: media type, file
/// size, URL, and the media comment warning when present.
struct BookMediaInfoSection: View {
  let book: Book

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Media Information")
        .font(.headline)

      VStack(alignment: .leading, spacing: 6) {
        DetailMetadataRow(
          systemImage: "doc.text.magnifyingglass",
          text: Text(book.media.mediaType.uppercased())
        )

        DetailMetadataRow(
          systemImage: "internaldrive",
          text: Text(book.size)
        )

        DetailMetadataRow(
          systemImage: "folder",
          text: Text(book.url)
        )

        if let comment = book.media.localizedComment {
          VStack(alignment: .leading, spacing: 2) {
            Image(systemName: AppIcon.loadError)
              .font(.caption)
              .foregroundColor(.orange)
            Text(comment)
              .font(.caption)
              .foregroundColor(.red)
              .textSelectionIfAvailable()
          }
        }
      }
    }
  }
}
