//
// PageFilmstripItemView.swift
//
//

import SwiftUI

/// One page thumbnail in the reader filmstrip. The current page's frame is
/// expanded by the strip; loading goes through the shared thumbnail cache.
struct PageFilmstripItemView: View {
  let bookId: String
  let pageNumber: Int
  let isCurrent: Bool
  let width: CGFloat
  let height: CGFloat
  let horizontalPadding: CGFloat
  let onTap: () -> Void

  @State private var image: PlatformImage?

  var body: some View {
    Button(action: onTap) {
      ZStack {
        if let image {
          Image(platformImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(.secondary.opacity(0.3))
        }
      }
      .frame(width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: 2))
      .opacity(isCurrent ? 1 : 0.7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, horizontalPadding)
    .task(id: "\(bookId)#\(pageNumber)") {
      guard image == nil else { return }
      if let url = try? await ThumbnailCache.shared.ensureThumbnail(
        id: bookId,
        type: .page,
        page: pageNumber
      ) {
        image = PlatformImage(contentsOfFile: url.path)
      }
    }
  }
}
