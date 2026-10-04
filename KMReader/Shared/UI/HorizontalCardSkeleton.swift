//
// HorizontalCardSkeleton.swift
//
//

import SwiftUI

/// Horizontal card skeleton: cover and text column form one button (one tvOS
/// focus target) on a cover-tinted rounded background, with a passive download
/// indicator and an ellipsis menu as separate trailing targets. Owns the tint
/// loading and the card chrome; cards supply their text column and menu.
struct HorizontalCardSkeleton<TextColumn: View, Menu: View>: View {
  let thumbnailId: String
  let thumbnailType: ThumbnailType
  var coverWidth: CGFloat = 56
  var shadowStyle: ShadowStyle = .basic
  var contentBlurRadius: CGFloat = 0
  var navigationLink: NavDestination? = nil
  var onAction: (() -> Void)? = nil
  var downloadIcon: String? = nil
  var downloadSpinning: Bool = false
  /// nil keeps the palette's meta color; failures pass red through here.
  var downloadColor: Color? = nil
  let textColumn: (HorizontalCardPalette) -> TextColumn
  let menu: () -> Menu

  @State private var tint = ThumbnailTint()

  init(
    thumbnailId: String,
    thumbnailType: ThumbnailType,
    coverWidth: CGFloat = 56,
    shadowStyle: ShadowStyle = .basic,
    contentBlurRadius: CGFloat = 0,
    navigationLink: NavDestination? = nil,
    onAction: (() -> Void)? = nil,
    downloadIcon: String? = nil,
    downloadSpinning: Bool = false,
    downloadColor: Color? = nil,
    @ViewBuilder textColumn: @escaping (HorizontalCardPalette) -> TextColumn,
    @ViewBuilder menu: @escaping () -> Menu
  ) {
    self.thumbnailId = thumbnailId
    self.thumbnailType = thumbnailType
    self.coverWidth = coverWidth
    self.shadowStyle = shadowStyle
    self.contentBlurRadius = contentBlurRadius
    self.navigationLink = navigationLink
    self.onAction = onAction
    self.downloadIcon = downloadIcon
    self.downloadSpinning = downloadSpinning
    self.downloadColor = downloadColor
    self.textColumn = textColumn
    self.menu = menu
  }

  private var palette: HorizontalCardPalette {
    HorizontalCardPalette(isTinted: tint.color != nil)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      mainContent

      accessories
    }
    .padding(LayoutConfig.horizontalCardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(tint.color ?? Color.cardBackground)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
    .animation(.appCurve(0.18), value: palette.isTinted)
    .contentShape(Rectangle())
    #if os(iOS)
      .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
    #endif
    .cardHoverEffect()
    .contextMenu {
      menu()
    }
    .task {
      tint.load(id: thumbnailId, type: thumbnailType)
    }
    .onReceive(NotificationCenter.default.publisher(for: .thumbnailDidRefresh)) { notification in
      tint.reloadIfMatches(notification)
    }
  }

  @ViewBuilder
  private var mainContent: some View {
    let label =
      HStack(alignment: .center, spacing: LayoutConfig.horizontalCardCoverSpacing) {
        ThumbnailImage(
          id: thumbnailId,
          type: thumbnailType,
          shadowStyle: shadowStyle,
          contentBlurRadius: contentBlurRadius,
          width: coverWidth,
          preserveAspectRatioOverride: false
        )
        .frame(width: coverWidth)
        .allowsHitTesting(false)

        VStack(alignment: .leading, spacing: 0) {
          textColumn(palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
      .contentShape(Rectangle())

    if let navigationLink {
      NavigationLink(value: navigationLink) {
        label
      }
      .adaptiveButtonStyle(.plain, hoverEffect: false)
    } else {
      Button {
        onAction?()
      } label: {
        label
      }
      .adaptiveButtonStyle(.plain, hoverEffect: false)
    }
  }

  @ViewBuilder
  private var accessories: some View {
    HStack(spacing: 6) {
      if let downloadIcon {
        DownloadStatusIcon(
          systemName: downloadIcon,
          spinning: downloadSpinning,
          color: downloadColor ?? palette.metaColor,
          bookId: thumbnailType == .book ? thumbnailId : nil
        )
        .font(.system(size: LayoutConfig.horizontalCardAccessoryIconSize))
      }

      EllipsisMenuButton(color: palette.metaColor, hoverEffect: false) {
        menu()
      }
      .font(.system(size: LayoutConfig.horizontalCardAccessoryIconSize, weight: .medium))
    }
    .padding(.trailing, 2)
  }
}
