//
// CircularThumbnailImage.swift
//
//

import SwiftUI

/// Circular cropped thumbnail loaded through the shared thumbnail cache.
/// `ThumbnailImage` slots are fixed to the cover aspect ratio, so circular
/// crops load the cached image directly and fill-clip it instead.
struct CircularThumbnailImage: View {
  let id: String
  var type: ThumbnailType = .book
  var diameter: CGFloat = 28

  @State private var image: PlatformImage?
  @State private var refreshTrigger = UUID()

  var body: some View {
    Group {
      if let image {
        Image(platformImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Circle()
          .fill(Color.secondary.opacity(0.15))
          .overlay {
            Image(systemName: "book")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
      }
    }
    .frame(width: diameter, height: diameter)
    .clipShape(Circle())
    .onReceive(NotificationCenter.default.publisher(for: .thumbnailDidRefresh)) { notification in
      guard let userInfo = notification.userInfo,
        let notificationId = userInfo["id"] as? String,
        let notificationType = userInfo["type"] as? String,
        notificationId == id,
        notificationType == type.rawValue
      else {
        return
      }
      refreshTrigger = UUID()
    }
    .task(id: "\(type.rawValue)|\(id)|\(refreshTrigger)") {
      image = await Self.load(id: id, type: type)
    }
  }

  private static func load(id: String, type: ThumbnailType) async -> PlatformImage? {
    await Task.detached(priority: .userInitiated) {
      guard let url = try? await ThumbnailCache.shared.ensureThumbnail(id: id, type: type),
        let image = PlatformImage(contentsOfFile: url.path)
      else { return nil }
      return await ImageDecodeHelper.decodeForDisplay(image)
    }.value
  }
}
