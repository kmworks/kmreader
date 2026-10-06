//
// BrowseContentTypeMenu.swift
//
//

import SwiftUI

/// Chip-style menu that switches a browse page between content types
/// (series, books, collections, read lists). Shows the current type.
struct BrowseContentTypeMenu: View {
  @Binding var selection: BrowseContentType
  let types: [BrowseContentType]
  /// Library-scope item counts, shown next to the type name when present.
  let counts: [BrowseContentType: Int]

  private func title(for type: BrowseContentType) -> String {
    if let count = counts[type] {
      return String(format: "%@ (%d)", type.displayName, count)
    }
    return type.displayName
  }

  var body: some View {
    Menu {
      Picker(selection: $selection) {
        ForEach(types) { type in
          Label(title(for: type), systemImage: type.icon).tag(type)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: selection.icon)
          .font(.caption2)
        Text(title(for: selection))
          .font(.caption)
          .fontWeight(.medium)
        Image(systemName: "chevron.down")
          .font(.caption2)
      }
    }
    .fixedSize()
    .adaptiveButtonStyle(.bordered)
    .optimizedControlSize()
  }
}
