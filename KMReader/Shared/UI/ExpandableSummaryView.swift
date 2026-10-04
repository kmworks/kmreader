//
// ExpandableSummaryView.swift
//
//

import SwiftUI

struct ExpandableSummaryView: View {
  let summary: String
  let title: String
  let titleIcon: String?
  let subtitle: String?
  let titleStyle: TitleStyle

  enum TitleStyle {
    case caption
    case headline
  }

  @State private var isExpanded = false
  @State private var fullTextHeight: CGFloat = 0
  @State private var collapsedTextHeight: CGFloat = 0

  private let collapsedLineLimit = 3
  private let heightTolerance: CGFloat = 1.0

  private var needsExpansion: Bool {
    let heightDifference = fullTextHeight - collapsedTextHeight
    return heightDifference > heightTolerance && collapsedTextHeight > 0 && fullTextHeight > 0
  }

  init(
    summary: String,
    title: String = String(localized: "Summary"),
    titleIcon: String? = "text.alignleft",
    subtitle: String? = nil,
    titleStyle: TitleStyle = .caption
  ) {
    self.summary = summary
    self.title = title
    self.titleIcon = titleIcon
    self.subtitle = subtitle
    self.titleStyle = titleStyle
  }

  private var titleView: some View {
    Group {
      switch titleStyle {
      case .caption:
        HStack(spacing: 4) {
          if let titleIcon = titleIcon {
            Image(systemName: titleIcon)
              .font(.caption)
          }
          Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
          if let subtitle = subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .foregroundColor(.secondary)
      case .headline:
        HStack {
          Text(title)
            .font(.headline)
          if let subtitle = subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      titleView

      Text(summary)
        .foregroundColor(.primary)
        .lineLimit(isExpanded ? nil : collapsedLineLimit)
        .textSelectionIfAvailable()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          VStack(spacing: 0) {
            Text(summary)
              .lineLimit(collapsedLineLimit)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if height > 0 {
                  collapsedTextHeight = height
                }
              }

            Text(summary)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if height > 0 {
                  fullTextHeight = height
                }
              }
          }
          .opacity(0)
        )

      if needsExpansion {
        ExpandToggleButton(isExpanded: $isExpanded)
      }
    }
  }
}
