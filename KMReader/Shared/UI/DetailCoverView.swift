//
// DetailCoverView.swift
//
//

import SwiftUI

/// Detail page cover with a context menu action to force-refresh the thumbnail.
struct DetailCoverView: View {
  let id: String
  let type: ThumbnailType
  let contentBlurRadius: CGFloat
  let width: CGFloat
  let cornerRadius: CGFloat

  init(
    id: String,
    type: ThumbnailType,
    contentBlurRadius: CGFloat = 0,
    width: CGFloat,
    cornerRadius: CGFloat = 8
  ) {
    self.id = id
    self.type = type
    self.contentBlurRadius = contentBlurRadius
    self.width = width
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    ThumbnailImage(
      id: id,
      type: type,
      contentBlurRadius: contentBlurRadius,
      width: width,
      cornerRadius: cornerRadius,
      isTransitionSource: false,
      onAction: {}
    ) {
    } menu: {
      Button {
        Task {
          do {
            try await ThumbnailCache.refreshThumbnail(id: id, type: type)
            ErrorManager.shared.notify(
              message: String(localized: "notification.cover.refreshed"))
          } catch {
            ErrorManager.shared.notify(
              message: String(localized: "notification.cover.refreshFailed"))
          }
        }
      } label: {
        Label(String(localized: "Refresh Cover"), systemImage: "arrow.clockwise")
      }
    }
  }
}
