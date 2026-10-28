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
          Image(systemName: "book.closed").foregroundStyle(.secondary)
        default:
          ProgressView()
        }
      }
      .frame(width: 40, height: 60)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 3) {
        Text(result.title).lineLimit(2)
        if let description = result.description, !description.isEmpty {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer()
    }
  }
}
