//
// BrowseStateView.swift
//
//

import SwiftUI

/// Generic state view for browse screens
struct BrowseStateView<Content: View, EmptyActions: View>: View {
  let isLoading: Bool
  let isEmpty: Bool
  let emptyIcon: String
  let emptyTitle: LocalizedStringKey
  let emptyMessage: LocalizedStringKey
  let onRetry: () -> Void
  @ViewBuilder let emptyActions: () -> EmptyActions
  @ViewBuilder let content: () -> Content

  init(
    isLoading: Bool,
    isEmpty: Bool,
    emptyIcon: String,
    emptyTitle: LocalizedStringKey,
    emptyMessage: LocalizedStringKey,
    onRetry: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content
  ) where EmptyActions == EmptyView {
    self.isLoading = isLoading
    self.isEmpty = isEmpty
    self.emptyIcon = emptyIcon
    self.emptyTitle = emptyTitle
    self.emptyMessage = emptyMessage
    self.onRetry = onRetry
    self.emptyActions = { EmptyView() }
    self.content = content
  }

  init(
    isLoading: Bool,
    isEmpty: Bool,
    emptyIcon: String,
    emptyTitle: LocalizedStringKey,
    emptyMessage: LocalizedStringKey,
    onRetry: @escaping () -> Void,
    @ViewBuilder emptyActions: @escaping () -> EmptyActions,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.isLoading = isLoading
    self.isEmpty = isEmpty
    self.emptyIcon = emptyIcon
    self.emptyTitle = emptyTitle
    self.emptyMessage = emptyMessage
    self.onRetry = onRetry
    self.emptyActions = emptyActions
    self.content = content
  }

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
          emptyActions()
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
