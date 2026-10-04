//
// SettingsBrowseCardPreview.swift
//
//

import SwiftUI

struct SettingsBrowseCardPreview: View {
  let title: String
  let subtitle: String?
  let detail: String
  let unreadCount: Int?
  let showCompletedBadge: Bool
  let shouldBlurCover: Bool
  let progress: Double?

  @AppStorage("coverOnlyCards") private var coverOnlyCards: Bool = false
  @AppStorage("cardTextOverlayMode") private var cardTextOverlayMode: Bool = false
  @AppStorage("showBookCardSeriesTitle") private var showBookCardSeriesTitle: Bool = true
  @AppStorage("thumbnailPreserveAspectRatio") private var thumbnailPreserveAspectRatio: Bool = true
  @AppStorage("thumbnailShowShadow") private var thumbnailShowShadow: Bool = true
  @AppStorage("thumbnailShowUnreadIndicator") private var thumbnailShowUnreadIndicator: Bool = true
  @AppStorage("thumbnailShowProgressBar") private var thumbnailShowProgressBar: Bool = true
  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  private let cornerRadius: CGFloat = 8
  private let imageCornerRadius: CGFloat = 6
  private let animation: Animation = .appCurve()

  private static let imageRatioExponentRange: ClosedRange<CGFloat> = -1...1

  @State private var imageRatio: CGFloat = Self.randomImageRatio()

  init(
    title: String,
    subtitle: String? = nil,
    detail: String,
    unreadCount: Int? = nil,
    showCompletedBadge: Bool = false,
    shouldBlurCover: Bool = false,
    progress: Double? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.detail = detail
    self.unreadCount = unreadCount
    self.showCompletedBadge = showCompletedBadge
    self.shouldBlurCover = shouldBlurCover
    self.progress = progress
  }

  private var shouldShowProgressBar: Bool {
    guard let progress = progress else { return false }
    return progress > 0 && progress < 1 && thumbnailShowProgressBar
  }

  private var shouldShowCompletedBadge: Bool {
    showCompletedBadge && thumbnailShowUnreadIndicator
  }

  private var shouldShowUnreadBadge: Bool {
    unreadCount != nil && thumbnailShowUnreadIndicator
  }

  private var spacing: CGFloat {
    if shouldShowProgressBar {
      return 4
    }
    return cardTextOverlayMode ? 0 : 12
  }

  private var imageFill: LinearGradient {
    LinearGradient(
      colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.24)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var effectiveShadowStyle: ShadowStyle {
    thumbnailShowShadow ? .platform : .none
  }

  private var effectivePreserveAspectRatio: Bool {
    thumbnailPreserveAspectRatio && !cardTextOverlayMode
  }

  private var shouldBlurPreviewCover: Bool {
    shouldBlurCover && thumbnailBlurUnreadCovers
  }

  private static func randomImageRatio() -> CGFloat {
    let exponent = CGFloat.random(in: imageRatioExponentRange)
    let scale = CGFloat(pow(2.0, Double(exponent)))
    return CoverAspectRatio.widthToHeight * scale
  }

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      coverView

      if shouldShowProgressBar, let progress = progress {
        ReadingProgressBar(progress: progress, type: .card, padsBottom: !cardTextOverlayMode)
      }

      if !cardTextOverlayMode && !coverOnlyCards {
        VStack(alignment: .leading, spacing: 4) {
          if let subtitle = subtitle, showBookCardSeriesTitle {
            Text(subtitle)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Text(title)
            .lineLimit(1)

          Text(detail)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .font(.footnote)
        .padding(.horizontal, PlatformHelper.progressBarHeight)
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .animation(animation, value: coverOnlyCards)
    .animation(animation, value: showBookCardSeriesTitle)
    .animation(animation, value: thumbnailPreserveAspectRatio)
    .animation(animation, value: thumbnailShowShadow)
    .animation(animation, value: thumbnailShowUnreadIndicator)
    .animation(animation, value: thumbnailShowProgressBar)
    .animation(animation, value: thumbnailBlurUnreadCovers)
    .animation(animation, value: cardTextOverlayMode)
  }

  private var coverView: some View {
    ZStack {
      Color.clear

      if effectivePreserveAspectRatio {
        imageCard
          .aspectRatio(imageRatio, contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      } else {
        imageCard
      }
    }
    .aspectRatio(CoverAspectRatio.widthToHeight, contentMode: .fit)
  }

  @ViewBuilder
  private var imageCard: some View {
    if shouldBlurPreviewCover {
      styledImageCard(
        baseImageCard
          .blur(radius: CoverBlurStyle.unreadRadius)
      )
    } else {
      styledImageCard(baseImageCard)
    }
  }

  private func styledImageCard<Content: View>(_ content: Content) -> some View {
    content
      .overlay { imageBorderOverlay }
      .shadowStyle(effectiveShadowStyle, cornerRadius: imageCornerRadius)
      .overlay {
        if cardTextOverlayMode {
          CardTextOverlay(cornerRadius: imageCornerRadius) {
            overlayTextContent
          }
        }
      }
      .overlay(alignment: .topTrailing) {
        if shouldShowUnreadBadge, let unreadCount = unreadCount {
          UnreadCountBadge(
            count: unreadCount,
            size: LayoutConfig.cardBadgeSize(cardWidth: LayoutConfig.gridCardWidth),
            cornerRadius: imageCornerRadius
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        } else if shouldShowCompletedBadge {
          CompletedIndicator(
            size: LayoutConfig.cardBadgeSize(cardWidth: LayoutConfig.gridCardWidth),
            cornerRadius: imageCornerRadius
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
      }
  }

  private var baseImageCard: some View {
    RoundedRectangle(cornerRadius: imageCornerRadius)
      .fill(imageFill)
      .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius))
  }

  @ViewBuilder
  private var overlayTextContent: some View {
    CardOverlayTextStack(
      title: title,
      subtitle: showBookCardSeriesTitle ? subtitle : nil
    ) {
      Text(detail)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private var imageBorderOverlay: some View {
    if !thumbnailShowShadow {
      RoundedRectangle(cornerRadius: imageCornerRadius)
        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
    }
  }
}
