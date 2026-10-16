//
// PageJumpPreviewCard.swift
//
//

import SwiftUI

/// Page preview card shared by the DIVINA and PDF jump sheets: thumbnail with
/// a selection ring/shadow and the page number below. Image loading stays with
/// the caller (page thumbnail cache vs PDFKit thumbnails).
struct PageJumpPreviewCard: View {
  let displayPage: Int
  let image: PlatformImage?
  let isSelected: Bool
  let imageHeight: CGFloat

  /// Card width relative to its height; callers use it for scroll margins.
  static let widthRatio: CGFloat = 0.72

  private var imageWidth: CGFloat {
    imageHeight * Self.widthRatio
  }

  var body: some View {
    VStack(spacing: 8) {
      Group {
        if let image {
          Image(platformImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
        } else {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .overlay {
              ProgressView()
            }
        }
      }
      .frame(width: imageWidth, height: imageHeight)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 3)
      )
      .shadow(
        color: Color.black.opacity(isSelected ? 0.3 : 0.15),
        radius: isSelected ? 8 : 4, x: 0, y: 2
      )
      .scaleEffect(isSelected ? 1.0 : 0.9)
      .animation(.appSpring, value: isSelected)

      Text("\(displayPage)")
        .font(.caption)
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isSelected ? Color.primary : .secondary)
    }
  }
}
