//
// ExpandToggleButton.swift
//
//

import SwiftUI

/// Show More/Show Less toggle for collapsing long detail-page sections.
struct ExpandToggleButton: View {
  @Binding var isExpanded: Bool

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
          .font(.caption2)
        Text(isExpanded ? "Show Less" : "Show More")
          .font(.caption)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
  }
}
