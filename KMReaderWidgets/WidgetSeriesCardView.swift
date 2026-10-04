//
//  WidgetSeriesCardView.swift
//  KMReaderWidgets
//

import SwiftUI
import WidgetKit

struct WidgetSeriesCardView: View {
  let entry: WidgetSeriesEntry

  var body: some View {
    Link(destination: WidgetDataStore.seriesDeepLinkURL(seriesId: entry.id)) {
      VStack(alignment: .leading, spacing: 4) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.secondary.opacity(0.16))
          .aspectRatio(2.0 / 3.0, contentMode: .fit)
          .overlay {
            thumbnailImage
          }
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
          }
          .overlay(alignment: .topTrailing) {
            if let unreadCount = entry.unreadCount, unreadCount > 0 {
              Text("\(unreadCount)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.52))
                .clipShape(Capsule())
                .padding(5)
            }
          }
          .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)

        Text(entry.title)
          .font(.caption2)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var thumbnailImage: some View {
    if let url = WidgetDataStore.thumbnailURL(for: entry),
      let imageData = try? Data(contentsOf: url),
      let uiImage = PlatformImage(data: imageData)
    {
      Image(platformImage: uiImage)
        .resizable()
        .scaledToFill()
    }
  }
}
