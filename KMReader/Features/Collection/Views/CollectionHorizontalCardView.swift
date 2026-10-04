//
// CollectionHorizontalCardView.swift
//
//

import SwiftUI

@MainActor
struct CollectionHorizontalCardView: View {
  let item: CollectionDisplayItem
  var coverWidth: CGFloat = 56
  var onChanged: () -> Void = {}
  let onDeleteRequested: () -> Void

  @State private var showEditSheet = false
  @State private var tint = ThumbnailTint()

  private var isTinted: Bool { tint.color != nil }

  private var titleColor: Color {
    isTinted ? .white : .primary
  }

  private var metaColor: Color {
    isTinted ? .white.opacity(0.7) : .secondary
  }

  private var collectionContextMenu: some View {
    CollectionContextMenu(
      collectionId: item.collectionId,
      isPinned: item.isPinned,
      onDeleteRequested: {
        onDeleteRequested()
      },
      onEditRequested: {
        showEditSheet = true
      },
      onPinToggleRequested: {
        togglePinned()
      }
    )
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      NavigationLink(
        value: NavDestination.collectionDetail(collectionId: item.collectionId)
      ) {
        HStack(alignment: .center, spacing: LayoutConfig.horizontalCardCoverSpacing) {
          ThumbnailImage(
            id: item.collectionId, type: .collection, width: coverWidth,
            preserveAspectRatioOverride: false
          )
          .frame(width: coverWidth)
          .allowsHitTesting(false)

          VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(item.name)
              .font(.system(size: LayoutConfig.horizontalCardFontSize, weight: .semibold))
              .foregroundColor(titleColor)
              .lineLimit(2)
              .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
              Text("\(item.seriesCount) series")
                .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))

              Text(item.lastModifiedDate.formattedMediumDate)
                .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
            }
            .foregroundColor(metaColor)

            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .adaptiveButtonStyle(.plain, hoverEffect: false)

      EllipsisMenuButton(color: metaColor, hoverEffect: false) {
        collectionContextMenu
      }
      .font(.system(size: LayoutConfig.horizontalCardAccessoryIconSize, weight: .medium))
      .padding(.trailing, 2)
    }
    .padding(LayoutConfig.horizontalCardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(tint.color ?? Color.cardBackground)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
    .animation(.appCurve(0.18), value: isTinted)
    .contentShape(Rectangle())
    #if os(iOS)
      .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
    #endif
    .cardHoverEffect()
    .contextMenu {
      collectionContextMenu
    }
    .task {
      tint.load(id: item.collectionId, type: .collection)
    }
    .onReceive(NotificationCenter.default.publisher(for: .thumbnailDidRefresh)) { notification in
      tint.reloadIfMatches(notification)
    }
    .sheet(isPresented: $showEditSheet, onDismiss: onChanged) {
      CollectionEditSheet(collection: item.collection)
    }
  }

  private func togglePinned() {
    let nextPinned = !item.isPinned
    Task {
      do {
        let database = try await DatabaseOperator.database()
        await database.setCollectionPinned(
          collectionId: item.collectionId,
          instanceId: item.instanceId,
          isPinned: nextPinned
        )
        onChanged()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
