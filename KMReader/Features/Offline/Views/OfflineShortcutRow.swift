//
// OfflineShortcutRow.swift
//
//

import SwiftUI

struct OfflineShortcutRow<Accessory: View>: View {
  let title: String
  let subtitle: String?
  let systemImage: String
  let color: Color
  let accessory: Accessory

  init(
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    color: Color,
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.color = color
    self.accessory = accessory()
  }

  init(
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    color: Color
  ) where Accessory == EmptyView {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.color = color
    self.accessory = EmptyView()
  }

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 10)
          .fill(color)
        Image(systemName: systemImage)
          .foregroundColor(.white)
      }
      .frame(width: 36, height: 36)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      accessory

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}
