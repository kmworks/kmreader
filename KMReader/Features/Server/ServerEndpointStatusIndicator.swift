//
// ServerEndpointStatusIndicator.swift
//

import SwiftUI

struct ServerEndpointStatusIndicator: View {
  let status: ServerEndpointProbeStatus?

  var body: some View {
    if let status {
      switch status {
      case .checking:
        ProgressView()
          .controlSize(.mini)
      case .reachable:
        dot(tint: .serverGreen)
      case .unauthorized:
        dot(tint: .orange)
      case .unreachable:
        dot(tint: .red)
      }
    }
  }

  private func dot(tint: Color) -> some View {
    Image(systemName: "circle.fill")
      .imageScale(.small)
      .foregroundStyle(tint)
  }
}
