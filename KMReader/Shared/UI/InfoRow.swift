//
// InfoRow.swift
//
//

import SwiftUI

struct InfoRow: View {
  let label: String
  let value: String
  let icon: String
  /// Commit-hash style values read better in a fixed-width font.
  var monospaced: Bool = false

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Label {
        Text(label)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundColor(.secondary)
      } icon: {
        Image(systemName: icon)
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(width: 16)
      }

      Spacer()

      Text(value)
        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
        .foregroundColor(.primary)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
        .textSelectionIfAvailable()
    }
  }
}
