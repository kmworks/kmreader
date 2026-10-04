//
// AdminRequiredView.swift
//
//

import SwiftUI

struct AdminRequiredView: View {
  var body: some View {
    Section {
      ContentUnavailableView {
        Label("Admin access required", systemImage: "lock.shield")
      } description: {
        Text("This feature is only available to administrators")
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical)
      .tvFocusableHighlight()
    }
  }
}
