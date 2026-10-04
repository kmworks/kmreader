//
// ReadListContinuationHorizontalCardView.swift
//
//

import SwiftUI

/// Horizontal card for a read list the user is reading: the next book's cover,
/// the read list's name, and how far along the list is. Opens the next book in
/// the read list's order.
@MainActor
struct ReadListContinuationHorizontalCardView: View {
  let continuation: ReadListContinuation
  var coverWidth: CGFloat = 56

  @Environment(\.readerActions) private var readerActions
  @State private var tint = ThumbnailTint()

  private var isTinted: Bool { tint.color != nil }

  private var titleColor: Color {
    isTinted ? .white : .primary
  }

  private var metaColor: Color {
    isTinted ? .white.opacity(0.7) : .secondary
  }

  private var continuationContextMenu: some View {
    ReadListContinuationContextMenu(continuation: continuation)
  }

  var body: some View {
    // Cover and text form a single button so they highlight together and form
    // one focus target on tvOS; the trailing accessories stay separate
    // targets, like Apple Books' cloud and ellipsis buttons.
    HStack(alignment: .center, spacing: 12) {
      Button {
        readerActions.open(continuation: continuation)
      } label: {
        HStack(alignment: .center, spacing: LayoutConfig.horizontalCardCoverSpacing) {
          ThumbnailImage(
            id: continuation.bookId,
            type: .book,
            shadowStyle: .platform,
            width: coverWidth,
            preserveAspectRatioOverride: false
          )
          .frame(width: coverWidth)
          .allowsHitTesting(false)

          VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(continuation.readListName)
              .font(.system(size: LayoutConfig.horizontalCardFontSize, weight: .semibold))
              .foregroundColor(titleColor)
              .lineLimit(2)
              .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
              Text(continuation.bookTitle)
                .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))
                .foregroundColor(isTinted ? .white.opacity(0.85) : .primary)
                .lineLimit(1)

              ReadListContinuationProgressText(continuation: continuation)
                .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
                .lineLimit(1)
            }
            .foregroundColor(metaColor)

            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .adaptiveButtonStyle(.plain, hoverEffect: false)

      accessories
    }
    .padding(LayoutConfig.horizontalCardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(tint.color ?? Color.cardBackground)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
    .animation(.easeInOut(duration: 0.18), value: isTinted)
    .contentShape(Rectangle())
    #if os(iOS)
      .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
    #endif
    .cardHoverEffect()
    .contextMenu {
      continuationContextMenu
    }
    .task {
      tint.load(id: continuation.bookId, type: .book)
    }
    .onReceive(NotificationCenter.default.publisher(for: .thumbnailDidRefresh)) { notification in
      tint.reloadIfMatches(notification)
    }
  }

  @ViewBuilder
  private var accessories: some View {
    HStack(spacing: 6) {
      if let icon = continuation.downloadStatus.displayIcon {
        DownloadStatusIcon(
          systemName: icon,
          spinning: continuation.downloadStatus.isPending,
          color: metaColor,
          bookId: continuation.bookId
        )
        .font(.system(size: LayoutConfig.horizontalCardAccessoryIconSize))
      }

      EllipsisMenuButton(color: metaColor, hoverEffect: false) {
        continuationContextMenu
      }
      .font(.system(size: LayoutConfig.horizontalCardAccessoryIconSize, weight: .medium))
    }
    .padding(.trailing, 2)
  }
}
