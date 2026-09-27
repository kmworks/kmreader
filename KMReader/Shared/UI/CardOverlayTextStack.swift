//
// CardOverlayTextStack.swift
//
//

import SwiftUI

struct CardOverlayTextStack<Detail: View>: View {
  let title: String
  let titleLeadingSystemImage: String?
  let subtitle: String?
  let subtitleLeadingSystemImage: String?
  let titleLineLimit: Int
  let style: CardOverlayTextStyle
  let spacing: CGFloat
  let detail: Detail

  init(
    title: String,
    titleLeadingSystemImage: String? = nil,
    subtitle: String? = nil,
    subtitleLeadingSystemImage: String? = nil,
    titleLineLimit: Int = 1,
    style: CardOverlayTextStyle = .standard,
    spacing: CGFloat = 4,
    @ViewBuilder detail: () -> Detail
  ) {
    self.title = title
    self.titleLeadingSystemImage = titleLeadingSystemImage
    self.subtitle = subtitle
    self.subtitleLeadingSystemImage = subtitleLeadingSystemImage
    self.titleLineLimit = titleLineLimit
    self.style = style
    self.spacing = spacing
    self.detail = detail()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      if let subtitle = subtitle {
        Group {
          if let subtitleLeadingSystemImage {
            Label(subtitle, systemImage: subtitleLeadingSystemImage)
              .labelStyle(.compact)
          } else {
            Text(subtitle)
          }
        }
        .cardOverlaySubtitle(style)
        .lineLimit(1)
      }

      if let titleLeadingSystemImage {
        HStack(spacing: 4) {
          Image(systemName: titleLeadingSystemImage)
          Text(title)
            .lineLimit(titleLineLimit)
        }
        .cardOverlayTitle(style)
      } else {
        Text(title)
          .cardOverlayTitle(style)
          .lineLimit(titleLineLimit)
      }

      detail
        .cardOverlayDetail(style)
    }
  }
}
