//
// OfflineCountBadge.swift
//
//

import SwiftUI

struct OfflineCountBadge: View {
  let count: Int

  var body: some View {
    Text(count, format: .number)
      .font(.caption2)
      .fontWeight(.semibold)
      .monospacedDigit()
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(LayoutConfig.neutralFillColor, in: Capsule())
      .foregroundColor(.secondary)
      .lineLimit(1)
  }
}
