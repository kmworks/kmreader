//
// SmartListCardView.swift
//
//

import SwiftUI

struct SmartListCardView: View {
  let smartList: SmartList
  /// Text styles scale with this width.
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("pinnedSmartListIds") private var pinnedStore: PinnedSmartListIds = .init()

  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false

  var body: some View {
    GridCardView(
      thumbnailId: smartList.id,
      thumbnailType: .smartList,
      title: smartList.name,
      cardWidth: cardWidth,
      navigationLink: NavDestination.smartListDetail(smartListId: smartList.id),
      titleLeadingSystemImage: pinnedStore.isPinned(
        smartListId: smartList.id, instanceId: current.instanceId) ? "pin.fill" : nil
    ) {
      SmartListContextMenu(
        smartList: smartList,
        onEditRequested: {
          showEditSheet = true
        },
        onDeleteRequested: {
          showDeleteConfirmation = true
        }
      )
    } detail: {
      Text(smartList.targetDisplayName)
    } overlayDetail: {
      Text(smartList.targetDisplayName)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .smartListItemActions(
      smartList: smartList,
      showEditSheet: $showEditSheet,
      showDeleteConfirmation: $showDeleteConfirmation
    )
  }
}
