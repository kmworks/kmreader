//
// DetailChip.swift
//
//

import SwiftUI

/// Filled capsule chip for detail-page metadata: one quiet neutral style,
/// no per-field colors. `glass: false` keeps the secondary-fill rendering
/// on every OS (genre/tag chips); glass chips use `glassEffect` on 26+.
struct DetailChip: View {
  let text: Text
  let systemImage: String?
  let glass: Bool

  init(_ label: String, systemImage: String? = nil, glass: Bool = true) {
    self.text = Text(label)
    self.systemImage = systemImage
    self.glass = glass
  }

  init(_ labelKey: LocalizedStringKey, systemImage: String? = nil, glass: Bool = true) {
    self.text = Text(labelKey)
    self.systemImage = systemImage
    self.glass = glass
  }

  var body: some View {
    let content = HStack(spacing: 4) {
      if let systemImage = systemImage {
        Image(systemName: systemImage)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      text
        .font(.caption)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)

    if glass, #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
      content
        .glassEffect(in: Capsule())
        .contentShape(Capsule())
    } else {
      content
        .background(LayoutConfig.neutralFillColor, in: Capsule())
        .contentShape(Capsule())
    }
  }
}
