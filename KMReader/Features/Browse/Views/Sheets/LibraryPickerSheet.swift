//
// LibraryPickerSheet.swift
//
//

import SwiftUI

struct LibraryPickerSheet: View {
  @State private var refreshTrigger = 0

  var body: some View {
    SheetView(title: String(localized: "Libraries"), size: .large, applyFormStyle: true) {
      LibraryListContent(
        selectionEnabled: true,
        forceMetricsOnAppear: false,
        enablePullToRefresh: false,
        refreshTrigger: refreshTrigger
      )
    } controls: {
      Button {
        refreshTrigger += 1
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
    }
  }
}
