//
// ReadListHorizontalCardView.swift
//
//

import SwiftUI

@MainActor
struct ReadListHorizontalCardView: View {
  let item: ReadListDisplayItem
  var coverWidth: CGFloat = 56
  var onChanged: () -> Void = {}
  let onDeleteRequested: () -> Void

  @State private var showEditSheet = false

  private var readListContextMenu: some View {
    ReadListContextMenu(
      readListId: item.readListId,
      downloadStatus: item.downloadStatus,
      offlinePolicy: item.offlinePolicy,
      offlinePolicyLimit: item.offlinePolicyLimit,
      isPinned: item.isPinned,
      onDeleteRequested: {
        onDeleteRequested()
      },
      onEditRequested: {
        showEditSheet = true
      },
      onPinToggleRequested: {
        togglePinned()
      },
      onMutationCompleted: onChanged
    )
  }

  var body: some View {
    HorizontalCardSkeleton(
      thumbnailId: item.readListId,
      thumbnailType: .readlist,
      coverWidth: coverWidth,
      navigationLink: NavDestination.readListDetail(readListId: item.readListId)
    ) { palette in
      Spacer(minLength: 0)

      Text(item.name)
        .font(.system(size: LayoutConfig.horizontalCardFontSize, weight: .semibold))
        .foregroundColor(palette.titleColor)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: 4) {
        Text("\(item.bookCount) books")
          .font(.system(size: LayoutConfig.horizontalCardSeriesFontSize))

        Text(item.lastModifiedDate.formattedMediumDate)
          .font(.system(size: LayoutConfig.horizontalCardMetaFontSize))
      }
      .foregroundColor(palette.metaColor)

      Spacer(minLength: 0)
    } menu: {
      readListContextMenu
    }
    .sheet(isPresented: $showEditSheet, onDismiss: onChanged) {
      ReadListEditSheet(readList: item.readList)
    }
  }

  private func togglePinned() {
    let nextPinned = !item.isPinned
    Task {
      do {
        let database = try await DatabaseOperator.database()
        await database.setReadListPinned(
          readListId: item.readListId,
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
