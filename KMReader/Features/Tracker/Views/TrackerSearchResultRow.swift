//
// TrackerSearchResultRow.swift
//

import SwiftUI

struct TrackerSearchResultRow: View {
  let result: TrackerSearchItem

  var body: some View {
    HStack(spacing: 12) {
      AsyncImage(url: result.coverUrl.flatMap(URL.init(string:))) { phase in
        switch phase {
        case .success(let image):
          image.resizable().aspectRatio(contentMode: .fill)
        case .failure:
          Image(systemName: ContentIcon.book).foregroundStyle(.secondary)
        default:
          if result.coverUrl == nil {
            Image(systemName: ContentIcon.book).foregroundStyle(.secondary)
          } else {
            ProgressView()
          }
        }
      }
      .frame(width: 40, height: 60)
      .background(LayoutConfig.neutralFillColor)
      .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 4) {
        Text(result.title)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
        if result.kindLabel != nil || result.tracked {
          HStack(spacing: 6) {
            if let kindLabel = result.kindLabel {
              Text(kindLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(LayoutConfig.neutralFillColor, in: RoundedRectangle(cornerRadius: 4))
            }
            if result.tracked {
              Label(String(localized: "In Your List"), systemImage: "bookmark")
                .symbolVariant(.fill)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
          }
        }
        if let description = result.description, !description.isEmpty {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
  }
}
