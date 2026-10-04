//
// LibraryRowTextContent.swift
//
//

import SwiftUI

/// Text column of a library row: name with an optional file size, and an
/// optional metrics line below.
struct LibraryRowTextContent: View {
  let name: String
  var fileSize: Double? = nil
  var metricsText: Text? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(name)
          .font(.headline)
        if let fileSize {
          Text(LibraryMetricsText.formatFileSize(fileSize))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      if let metricsText {
        metricsText
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}
