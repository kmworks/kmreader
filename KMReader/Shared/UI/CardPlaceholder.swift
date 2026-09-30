//
// CardPlaceholder.swift
//
//

import SwiftUI

/// Placeholder skeleton view for cards while data is loading
struct CardPlaceholder: View {
  let layout: BrowseLayoutMode
  let kind: CardPlaceholderKind
  var showBookSeriesTitle: Bool = true
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth
  var coverOnly: Bool = false

  @AppStorage("showBookCardSeriesTitle") private var showBookCardSeriesTitle: Bool = true
  @AppStorage("coverOnlyCards") private var coverOnlyCards: Bool = false
  @AppStorage("cardTextOverlayMode") private var cardTextOverlayMode: Bool = false
  @AppStorage("thumbnailShowProgressBar") private var thumbnailShowProgressBar: Bool = true

  private let cornerRadius: CGFloat = 8
  private let lineSpacing: CGFloat = 6

  private var listThumbnailWidth: CGFloat {
    switch kind {
    case .series:
      return 80
    case .book, .collection, .readList:
      return 60
    }
  }

  private var listThumbnailHeight: CGFloat {
    listThumbnailWidth / CoverAspectRatio.widthToHeight
  }

  private var showsBookSeriesTitleLine: Bool {
    kind == .book && showBookSeriesTitle && showBookCardSeriesTitle
  }

  /// Cover-only cards never render the text overlay, even in overlay mode.
  private var showsTextOverlay: Bool {
    cardTextOverlayMode && !coverOnly
  }

  private var reservesBookProgressBar: Bool {
    kind == .book && thumbnailShowProgressBar
  }

  private var gridTextStyle: LayoutConfig.CardTextStyle {
    LayoutConfig.cardTextStyle(cardWidth: cardWidth)
  }

  private var gridContentSpacing: CGFloat {
    if reservesBookProgressBar {
      return 2
    }
    if showsTextOverlay {
      return 0
    }
    return 12
  }

  var body: some View {
    switch layout {
    case .grid, .largeGrid:
      gridPlaceholder
    case .list:
      listPlaceholder
    }
  }

  private var gridPlaceholder: some View {
    VStack(alignment: .leading, spacing: gridContentSpacing) {
      gridThumbnail

      if reservesBookProgressBar {
        ReadingProgressBar(progress: 0, type: .card, padsBottom: !showsTextOverlay)
          .opacity(0)
      }

      if !showsTextOverlay && !coverOnlyCards && !coverOnly {
        VStack(alignment: .leading) {
          ForEach(Array(gridLines.enumerated()), id: \.offset) { item in
            placeholderLine(
              textStyle: item.element.textStyle,
              text: item.element.text,
              widthScale: item.element.width,
              opacity: item.element.opacity
            )
          }
        }
        .padding(.horizontal, PlatformHelper.progressBarHeight)
      }
    }
  }

  private var gridThumbnail: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.gray.opacity(0.2))

      if showsTextOverlay {
        CardTextOverlay(cornerRadius: cornerRadius) {
          ForEach(Array(gridLines.enumerated()), id: \.offset) { item in
            placeholderLine(
              textStyle: item.element.textStyle,
              text: item.element.text,
              widthScale: item.element.width,
              opacity: item.element.opacity
            )
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    .aspectRatio(CoverAspectRatio.widthToHeight, contentMode: .fit)
  }

  private var listPlaceholder: some View {
    HStack(alignment: .top, spacing: 12) {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.gray.opacity(0.2))
        .frame(width: listThumbnailWidth)
        .frame(height: listThumbnailHeight)

      VStack(alignment: .leading, spacing: lineSpacing) {
        ForEach(Array(listLines.enumerated()), id: \.offset) { item in
          placeholderLine(
            textStyle: item.element.textStyle,
            text: item.element.text,
            widthScale: item.element.width,
            opacity: item.element.opacity
          )
        }
      }
    }
  }

  private var gridLines: [(textStyle: Font.TextStyle, text: String, width: CGFloat, opacity: Double)] {
    switch kind {
    case .book:
      let titleLines: [(textStyle: Font.TextStyle, text: String, width: CGFloat, opacity: Double)] = [
        (textStyle: gridTextStyle.title, text: "1 - Book Title", width: 0.85, opacity: 0.2),
        (textStyle: gridTextStyle.secondary, text: "200 pages", width: 0.6, opacity: 0.15),
      ]
      guard showsBookSeriesTitleLine else { return titleLines }
      return [
        (textStyle: gridTextStyle.secondary, text: "Series Title", width: 0.55, opacity: 0.18)
      ] + titleLines
    case .series:
      return [
        (textStyle: gridTextStyle.title, text: "Series Title", width: 0.8, opacity: 0.2),
        (textStyle: gridTextStyle.secondary, text: "12 books", width: 0.6, opacity: 0.15),
      ]
    case .collection:
      return [
        (textStyle: .footnote, text: "Collection Name", width: 0.75, opacity: 0.2),
        (textStyle: .footnote, text: "8 series", width: 0.5, opacity: 0.15),
      ]
    case .readList:
      return [
        (textStyle: .footnote, text: "Read List Name", width: 0.75, opacity: 0.2),
        (textStyle: .footnote, text: "12 books", width: 0.5, opacity: 0.15),
      ]
    }
  }

  private var listLines: [(textStyle: Font.TextStyle, text: String, width: CGFloat, opacity: Double)] {
    switch kind {
    case .book:
      let titleLines: [(textStyle: Font.TextStyle, text: String, width: CGFloat, opacity: Double)] = [
        (textStyle: .body, text: "#12 - Book Title", width: 0.85, opacity: 0.2),
        (textStyle: .caption, text: "Last Updated", width: 0.6, opacity: 0.15),
        (textStyle: .footnote, text: "200 pages 120 MB", width: 0.7, opacity: 0.15),
      ]
      guard showsBookSeriesTitleLine else { return titleLines }
      return [
        (textStyle: .footnote, text: "Series Title", width: 0.55, opacity: 0.18)
      ] + titleLines
    case .series:
      return [
        (textStyle: .callout, text: "Series Title", width: 0.85, opacity: 0.2),
        (textStyle: .footnote, text: "Ongoing", width: 0.5, opacity: 0.15),
        (textStyle: .caption, text: "Last Updated", width: 0.6, opacity: 0.15),
        (textStyle: .footnote, text: "12 books 3 unread", width: 0.75, opacity: 0.15),
      ]
    case .collection:
      return [
        (textStyle: .callout, text: "Collection Name", width: 0.8, opacity: 0.2),
        (textStyle: .footnote, text: "8 series", width: 0.5, opacity: 0.15),
        (textStyle: .caption, text: "Last Updated", width: 0.6, opacity: 0.15),
      ]
    case .readList:
      return [
        (textStyle: .callout, text: "Read List Name", width: 0.8, opacity: 0.2),
        (textStyle: .footnote, text: "12 books", width: 0.5, opacity: 0.15),
        (textStyle: .caption, text: "Last Updated", width: 0.6, opacity: 0.15),
        (textStyle: .caption, text: "Short summary", width: 0.75, opacity: 0.15),
      ]
    }
  }

  private func placeholderLine(
    textStyle: Font.TextStyle,
    text: String,
    widthScale: CGFloat,
    opacity: Double
  ) -> some View {
    Text(text)
      .font(Font.system(textStyle))
      .foregroundColor(.clear)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color.gray.opacity(opacity))
          .frame(maxWidth: .infinity, alignment: .leading)
          .scaleEffect(x: widthScale, anchor: .leading)
      }
      .accessibilityHidden(true)
  }
}
