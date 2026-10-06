//
// ReaderUnavailableView.swift
//
//

import SwiftUI

struct ReaderUnavailableView: View {
  let icon: String
  let title: LocalizedStringKey
  let message: String?
  let onRetry: (() -> Void)?
  let onClose: () -> Void

  init(
    icon: String,
    title: LocalizedStringKey,
    message: String? = nil,
    onRetry: (() -> Void)? = nil,
    onClose: @escaping () -> Void
  ) {
    self.icon = icon
    self.title = title
    self.message = message
    self.onRetry = onRetry
    self.onClose = onClose
  }

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: icon)
        .font(.system(size: 60))
        .foregroundColor(.secondary)

      VStack(spacing: 8) {
        Text(title)
          .font(.headline)
        if let message, !message.isEmpty {
          Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
      }

      HStack(spacing: 12) {
        if let onRetry {
          Button {
            onRetry()
          } label: {
            Label("Retry", systemImage: AppIcon.refresh)
              .font(.headline)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
          }
          .adaptiveButtonStyle(.borderedProminent)
        }

        Button {
          onClose()
        } label: {
          Label("Close", systemImage: "xmark.circle.fill")
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .adaptiveButtonStyle(onRetry == nil ? .borderedProminent : .bordered)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .background(PlatformHelper.systemBackgroundColor.readerIgnoresSafeArea())
  }
}
