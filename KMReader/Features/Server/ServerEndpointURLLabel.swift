//
// ServerEndpointURLLabel.swift
//

import SwiftUI

/// Single-line server URL with an inline reachability dot and optional
/// latency/status suffix. The URL truncates first; the suffix stays intact.
struct ServerEndpointURLLabel: View {
  let url: String
  let status: ServerEndpointProbeStatus?
  var font: Font = .caption
  var showsDetail: Bool = true

  var body: some View {
    HStack(spacing: 5) {
      ServerEndpointStatusIndicator(status: status)
      Text(ServerEndpoint.displayURL(for: url))
        .lineLimit(1)
        .truncationMode(.middle)
        .layoutPriority(1)
      if showsDetail, let detail = ServerEndpointStatusLabel.detailText(for: status) {
        (Text(verbatim: "· ") + Text(detail))
          .foregroundStyle(ServerEndpointStatusLabel.detailColor(for: status))
          .lineLimit(1)
          .layoutPriority(2)
      }
    }
    .font(font)
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }
}
