//
// GridCardView.swift
//
//

import SwiftUI

/// Large/small grid card skeleton: cover with optional badge and text overlay,
/// progress bar row, and a text block. Owns the card preferences (cover-only
/// cards, text overlay mode, progress bar, blurred unread covers) so every
/// grid card renders them identically; cards supply their badge, menu, and
/// status line through the slots.
struct GridCardView<Badge: View, Menu: View, Detail: View, OverlayDetail: View>: View {
  let thumbnailId: String
  let thumbnailType: ThumbnailType
  let title: String
  var coverOnly: Bool = false
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth
  var isUnread: Bool = false
  var navigationLink: NavDestination? = nil
  var onAction: (() -> Void)? = nil
  var titleLineLimit: Int = 1
  var subtitle: String? = nil
  /// Leading icon for the subtitle line (oneshot cards mark the author line with a book).
  var subtitleLeadingSystemImage: String? = nil
  var downloadIcon: String? = nil
  var downloadSpinning: Bool = false
  /// nil drops the progress bar row and the overlay progress slot entirely.
  var progress: Double? = nil
  var isInProgress: Bool = false
  let badge: Badge
  let menu: Menu
  let detail: Detail
  let overlayDetail: OverlayDetail

  @AppStorage("coverOnlyCards") private var coverOnlyCards: Bool = false
  @AppStorage("cardTextOverlayMode") private var cardTextOverlayMode: Bool = false
  @AppStorage("thumbnailShowProgressBar") private var thumbnailShowProgressBar: Bool = true
  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  init(
    thumbnailId: String,
    thumbnailType: ThumbnailType,
    title: String,
    coverOnly: Bool = false,
    cardWidth: CGFloat = LayoutConfig.gridCardWidth,
    isUnread: Bool = false,
    navigationLink: NavDestination? = nil,
    onAction: (() -> Void)? = nil,
    titleLineLimit: Int = 1,
    subtitle: String? = nil,
    subtitleLeadingSystemImage: String? = nil,
    downloadIcon: String? = nil,
    downloadSpinning: Bool = false,
    progress: Double? = nil,
    isInProgress: Bool = false,
    @ViewBuilder badge: () -> Badge,
    @ViewBuilder menu: () -> Menu,
    @ViewBuilder detail: () -> Detail,
    @ViewBuilder overlayDetail: () -> OverlayDetail
  ) {
    self.thumbnailId = thumbnailId
    self.thumbnailType = thumbnailType
    self.title = title
    self.coverOnly = coverOnly
    self.cardWidth = cardWidth
    self.isUnread = isUnread
    self.navigationLink = navigationLink
    self.onAction = onAction
    self.titleLineLimit = titleLineLimit
    self.subtitle = subtitle
    self.subtitleLeadingSystemImage = subtitleLeadingSystemImage
    self.downloadIcon = downloadIcon
    self.downloadSpinning = downloadSpinning
    self.progress = progress
    self.isInProgress = isInProgress
    self.badge = badge()
    self.menu = menu()
    self.detail = detail()
    self.overlayDetail = overlayDetail()
  }

  /// Cover-only cards never render the text overlay, even in overlay mode.
  private var showsTextOverlay: Bool {
    cardTextOverlayMode && !coverOnly
  }

  private var contentSpacing: CGFloat {
    if progress != nil && thumbnailShowProgressBar {
      return 2
    }
    if showsTextOverlay {
      return 0
    }
    return 12
  }

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  private var titleTextStyle: Font.TextStyle {
    LayoutConfig.cardTitleTextStyle(cardWidth: cardWidth)
  }

  private var secondaryTextStyle: Font.TextStyle {
    LayoutConfig.cardSecondaryTextStyle(cardWidth: cardWidth)
  }

  private var tertiaryTextStyle: Font.TextStyle {
    LayoutConfig.cardTertiaryTextStyle(cardWidth: cardWidth)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: contentSpacing) {
      ThumbnailImage(
        id: thumbnailId,
        type: thumbnailType,
        shadowStyle: .platform,
        contentBlurRadius: coverBlurRadius,
        alignment: .bottom,
        navigationLink: navigationLink,
        preserveAspectRatioOverride: showsTextOverlay ? false : nil,
        onAction: onAction
      ) {
        ZStack {
          if showsTextOverlay {
            CardTextOverlay(cornerRadius: 8) {
              overlayTextContent
            }
          }
          badge
        }
      } menu: {
        menu
      }

      if let progress, thumbnailShowProgressBar {
        ReadingProgressBar(progress: progress, type: .card, padsBottom: !showsTextOverlay)
          .opacity(isInProgress ? 1 : 0)
      }

      if !showsTextOverlay && !coverOnlyCards && !coverOnly {
        VStack(alignment: .leading) {
          if let subtitle {
            Group {
              if let subtitleLeadingSystemImage {
                Label(subtitle, systemImage: subtitleLeadingSystemImage)
              } else {
                Text(subtitle)
              }
            }
            .font(.system(secondaryTextStyle))
            .foregroundColor(.secondary)
            .lineLimit(1)
          }

          Text(title)
            .lineLimit(titleLineLimit)

          HStack(spacing: 4) {
            detail
            if let downloadIcon {
              Spacer()
              DownloadStatusIcon(systemName: downloadIcon, spinning: downloadSpinning)
                .font(.system(tertiaryTextStyle))
            }
          }
          .font(.system(secondaryTextStyle))
          .foregroundColor(.secondary)
        }
        .font(.system(titleTextStyle))
        // Match the progress bar's horizontal inset.
        .padding(.horizontal, PlatformHelper.progressBarHeight)
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var overlayTextContent: some View {
    let style = CardOverlayTextStyle.standard

    CardOverlayTextStack(
      title: title,
      subtitle: subtitle,
      subtitleLeadingSystemImage: subtitleLeadingSystemImage,
      titleLineLimit: titleLineLimit,
      style: style
    ) {
      HStack(spacing: 4) {
        overlayDetail
        if let downloadIcon {
          Spacer()
          // Overlay mode renders the icon in white over the cover, which
          // calls for the filled variant.
          DownloadStatusIcon(
            systemName: downloadIcon, spinning: downloadSpinning, color: style.secondaryColor
          )
          .font(.caption2)
        }
      }
    }
  }
}

extension GridCardView where Badge == EmptyView {
  init(
    thumbnailId: String,
    thumbnailType: ThumbnailType,
    title: String,
    coverOnly: Bool = false,
    cardWidth: CGFloat = LayoutConfig.gridCardWidth,
    isUnread: Bool = false,
    navigationLink: NavDestination? = nil,
    onAction: (() -> Void)? = nil,
    titleLineLimit: Int = 1,
    subtitle: String? = nil,
    subtitleLeadingSystemImage: String? = nil,
    downloadIcon: String? = nil,
    downloadSpinning: Bool = false,
    progress: Double? = nil,
    isInProgress: Bool = false,
    @ViewBuilder menu: () -> Menu,
    @ViewBuilder detail: () -> Detail,
    @ViewBuilder overlayDetail: () -> OverlayDetail
  ) {
    self.init(
      thumbnailId: thumbnailId,
      thumbnailType: thumbnailType,
      title: title,
      coverOnly: coverOnly,
      cardWidth: cardWidth,
      isUnread: isUnread,
      navigationLink: navigationLink,
      onAction: onAction,
      titleLineLimit: titleLineLimit,
      subtitle: subtitle,
      subtitleLeadingSystemImage: subtitleLeadingSystemImage,
      downloadIcon: downloadIcon,
      downloadSpinning: downloadSpinning,
      progress: progress,
      isInProgress: isInProgress,
      badge: { EmptyView() },
      menu: menu,
      detail: detail,
      overlayDetail: overlayDetail
    )
  }
}
