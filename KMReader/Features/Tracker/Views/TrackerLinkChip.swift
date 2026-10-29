//
// TrackerLinkChip.swift
//

import SwiftUI

struct TrackerLinkChip: View {
  let link: TrackerLink
  let state: TrackerRemoteState?
  let requiresLogin: Bool

  var body: some View {
    HStack(spacing: 6) {
      TrackerLogo(provider: link.provider)
        .frame(width: 16, height: 16)
      Text(link.provider.displayName)
      if requiresLogin {
        Circle()
          .fill(.red)
          .frame(width: 6, height: 6)
          .accessibilityLabel(Text(String(localized: "Login Required")))
      } else if let status = state?.status {
        Text(status.displayName)
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption.weight(.medium))
    .lineLimit(1)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(LayoutConfig.neutralFillColor, in: Capsule())
    .overlay {
      Capsule()
        .strokeBorder(Color.secondary.opacity(0.2))
    }
    .contentShape(Capsule())
  }
}
