//
// SidebarItemLabel.swift
//
//

import SwiftUI

struct SidebarItemLabel: View {
  let title: String
  let count: Int?
  let systemImage: String?

  init(title: String, count: Int?, systemImage: String? = nil) {
    self.title = title
    self.count = count
    self.systemImage = systemImage
  }

  var body: some View {
    HStack {
      if let systemImage {
        Label(title, systemImage: systemImage).lineLimit(1)
      } else {
        Text(title).lineLimit(1)
      }
      Spacer()
      if let count {
        Text("\(count)")
          .font(.caption2)
          // Hierarchical styles derive from the row's actual foreground, so
          // the badge stays readable on the inverted selected-row pill.
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.secondary.opacity(0.1), in: Capsule())
      }
    }
  }
}
