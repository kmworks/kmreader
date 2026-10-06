//
// SimpleSortOptionsSheet.swift
//
//

import SwiftUI

struct SimpleSortOptionsSheet: View {
  @Binding var sortOpts: SimpleSortOptions
  @Environment(\.dismiss) private var dismiss
  @State private var tempOpts: SimpleSortOptions

  init(sortOpts: Binding<SimpleSortOptions>) {
    self._sortOpts = sortOpts
    self._tempOpts = State(initialValue: sortOpts.wrappedValue)
  }

  var body: some View {
    SheetView(
      title: String(localized: "Sort"), size: .both, onReset: resetOptions, applyFormStyle: true
    ) {
      Form {
        SortOptionView(
          sortField: $tempOpts.sortField,
          sortDirection: $tempOpts.sortDirection
        )

      }
    } controls: {
      Button(action: applyChanges) {
        Label("Done", systemImage: AppIcon.confirm)
      }
    }
  }

  private func resetOptions() {
    withAnimation {
      tempOpts = SimpleSortOptions()
    }
  }

  private func applyChanges() {
    if tempOpts != sortOpts {
      sortOpts = tempOpts
    }
    dismiss()
  }
}
