//
// ServerEndpointStatusLabel.swift
//

import SwiftUI

/// Quiet inline reachability/latency label: a small status dot (or mini
/// spinner) followed by plain text. State color is text/dot only, never a
/// tinted capsule fill.
struct ServerEndpointStatusLabel: View {
  let status: ServerEndpointProbeStatus?

  var body: some View {
    if let status {
      HStack(spacing: 4) {
        ServerEndpointStatusIndicator(status: status)
        if let text = Self.detailText(for: status) {
          Text(text)
            .foregroundStyle(Self.detailColor(for: status))
        }
      }
      .font(.caption)
      .monospacedDigit()
    }
  }

  static func detailText(for status: ServerEndpointProbeStatus?) -> String? {
    switch status {
    case .reachable(let milliseconds):
      return String(localized: "\(milliseconds) ms")
    case .unauthorized:
      return String(localized: "Auth Failed")
    case .unreachable:
      return String(localized: "Unreachable")
    case .checking, nil:
      return nil
    }
  }

  static func detailColor(for status: ServerEndpointProbeStatus?) -> Color {
    switch status {
    case .unauthorized:
      return .orange
    case .unreachable:
      return .red
    case .reachable, .checking, nil:
      return .secondary
    }
  }
}
