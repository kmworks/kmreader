//
// CollectionSortView.swift
//
//

import SwiftUI

struct CollectionSortView: View {
  @AppStorage("collectionSortOptions") private var sortOpts: SimpleSortOptions =
    SimpleSortOptions()
  @Binding var showFilterSheet: Bool
  var layoutMode: Binding<BrowseLayoutMode>? = nil

  var sortString: String {
    return
      "\(sortOpts.sortField.displayName) \(sortOpts.sortDirection == .ascending ? "↑" : "↓")"
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        if let layoutMode {
          LayoutModeMenu(selection: layoutMode)
        }

        Image(systemName: "arrow.up.arrow.down.circle")
          .padding(.leading, 4)
          .foregroundColor(.secondary)

        FilterChip(
          label: sortString,
          systemImage: "arrow.up.arrow.down",
          openSheet: $showFilterSheet
        )
      }
      .padding(4)
    }
    .scrollClipDisabled()
    .sheet(isPresented: $showFilterSheet) {
      SimpleSortOptionsSheet(sortOpts: $sortOpts)
    }
  }
}
