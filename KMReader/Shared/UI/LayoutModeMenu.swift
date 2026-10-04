//
// LayoutModeMenu.swift
//
//

import SwiftUI

/// Chip-row menu that switches a browse page between row, medium, and large
/// card layouts. Shows the current layout's icon.
struct LayoutModeMenu: View {
  @Binding var selection: BrowseLayoutMode

  /// Layout switches are content changes, so the write goes through
  /// withAnimation for every page instead of each page wrapping its own
  /// binding.
  private var animatedSelection: Binding<BrowseLayoutMode> {
    Binding(
      get: { selection },
      set: { newValue in
        withAnimation {
          selection = newValue
        }
      }
    )
  }

  var body: some View {
    Menu {
      Picker(selection: animatedSelection) {
        ForEach(BrowseLayoutMode.allCases) { mode in
          Label(mode.displayName, systemImage: mode.iconName).tag(mode)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      // The blank caption-text line keeps the menu as tall as sibling FilterChips,
      // whose height comes from their caption text rather than the icon.
      ZStack {
        Text(verbatim: " ")
          .font(.caption)
          .fontWeight(.medium)
          .accessibilityHidden(true)
        Label(selection.displayName, systemImage: selection.iconName)
          .labelStyle(.iconOnly)
          .font(.caption)
      }
      .frame(width: 16)
    }
    .fixedSize()
    .adaptiveButtonStyle(.bordered)
    .optimizedControlSize()
  }
}
