//
// ReadListContinuationContextMenu.swift
//
//

import SwiftUI

/// Long-press menu of a read list continuation card, whatever its card kind:
/// the read list's details and Stop Reading.
struct ReadListContinuationContextMenu: View {
  let continuation: ReadListContinuation

  @AppStorage("currentAccount") private var current: Current = .init()

  var body: some View {
    NavigationLink(value: NavDestination.readListDetail(readListId: continuation.readListId)) {
      Label("View Details", systemImage: AppIcon.details)
    }
    ReadListStopReadingButton(readListId: continuation.readListId, instanceId: current.instanceId)
  }
}
