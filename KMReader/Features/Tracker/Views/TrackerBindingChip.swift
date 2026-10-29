//
// TrackerBindingChip.swift
//

import SwiftUI

struct TrackerBindingChip: View {
  let link: TrackerLink

  var body: some View {
    HStack(spacing: 4) {
      TrackerLogo(provider: link.provider)
        .frame(width: 14, height: 14)
      Text(link.provider.displayName)
        .foregroundStyle(.primary)
      Text(link.trackMode.displayName)
        .foregroundStyle(.secondary)
      if link.chapterOffset != 0 {
        Text(verbatim: link.chapterOffset > 0 ? "+\(link.chapterOffset)" : "\(link.chapterOffset)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption2.weight(.medium))
    .lineLimit(1)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(LayoutConfig.neutralFillColor, in: Capsule())
  }
}
