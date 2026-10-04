//
// DetailTimestampsView.swift
//
//

import SwiftUI

/// Created/modified dates as a quiet caption row, kept out of chip
/// chrome so detail pages don't accumulate visual noise.
struct DetailTimestampsView: View {
  let created: Date
  let lastModified: Date

  var body: some View {
    HStack(spacing: 12) {
      Label(
        "Created: \(created.formattedMediumDate)",
        systemImage: "calendar.badge.plus"
      )
      .lineLimit(2)
      Label(
        "Modified: \(lastModified.formattedMediumDate)",
        systemImage: "clock"
      )
      .lineLimit(2)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    // Large dynamic type wraps to a second line instead of overflowing.
    .fixedSize(horizontal: false, vertical: true)
  }
}
