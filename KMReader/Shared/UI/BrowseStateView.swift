//
// BrowseStateView.swift
//
//

import SwiftUI

/// Generic state view for browse screens
struct BrowseStateView<Content: View>: View {
  let isLoading: Bool
  let isEmpty: Bool
  let emptyIcon: String
  let emptyTitle: LocalizedStringKey
  let emptyMessage: LocalizedStringKey
  let onRetry: () -> Void
  @ViewBuilder let content: () -> Content

  var body: some View {
    Group {
      if isLoading && isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      } else if isEmpty {
        ContentUnavailableView {
          Label(emptyTitle, systemImage: emptyIcon)
        } description: {
          Text(emptyMessage)
        } actions: {
          Button(String(localized: "Retry")) {
            onRetry()
          }
          .adaptiveButtonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        content()

        if isLoading {
          ProgressView()
            .padding()
        }
      }
    }
  }
}
