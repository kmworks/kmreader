//
// ServerEndpointRowView.swift
//

import SwiftUI

struct ServerEndpointRowView: View {
  let endpoint: ServerEndpoint
  let status: ServerEndpointProbeStatus?
  let isActive: Bool
  let isSwitching: Bool
  let isDisabled: Bool
  let onSelect: () -> Void

  var body: some View {
    Button {
      onSelect()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
          .font(.body)
          .foregroundStyle(isActive ? Color.serverGreen : Color.secondary.opacity(0.5))

        VStack(alignment: .leading, spacing: 2) {
          Text(endpoint.displayName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
          if endpoint.hasCustomName {
            Text(endpoint.displayURL)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }

        Spacer(minLength: 8)

        if isSwitching {
          ProgressView()
            .controlSize(.small)
        } else {
          ServerEndpointStatusLabel(status: status)
        }
      }
      .padding(.vertical, 4)
      .contentShape(Rectangle())
    }
    .adaptiveButtonStyle(.plain)
    .disabled(isDisabled || isActive)
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}
