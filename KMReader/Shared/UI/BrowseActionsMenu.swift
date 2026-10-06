//
// BrowseActionsMenu.swift
//
//

import SwiftUI

/// Trailing ellipsis menu for browse pages (Library tab, Browse, Offline) on
/// iOS and macOS: a copy of the chip row's layout / presets / filter entries,
/// so every page keeps a single trailing toolbar button. Callers bind the
/// same per-type `*BrowseLayout` AppStorage keys as the chip row's
/// LayoutModeMenu, so both stay in sync without re-threading state.
struct BrowseActionsMenu: View {
  @Binding var layoutMode: BrowseLayoutMode
  let showsPresets: Bool
  /// Off only while the iPhone Search tab shows its placeholder: the filter
  /// sheet is hosted by the per-type chip row, which does not exist until
  /// results render, so a tap there would stick the presentation flag.
  let isFilterEnabled: Bool
  let onShowPresets: () -> Void
  let onShowFilter: () -> Void

  /// Same treatment as LayoutModeMenu: layout switches animate everywhere.
  private var animatedLayoutMode: Binding<BrowseLayoutMode> {
    Binding(
      get: { layoutMode },
      set: { newValue in
        withAnimation {
          layoutMode = newValue
        }
      }
    )
  }

  var body: some View {
    Menu {
      Picker(selection: animatedLayoutMode) {
        ForEach(BrowseLayoutMode.allCases) { mode in
          Label(mode.displayName, systemImage: mode.iconName).tag(mode)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()

      Divider()

      if showsPresets {
        Button {
          deferMenuActionPresentation { onShowPresets() }
        } label: {
          Label(String(localized: "Presets"), systemImage: "bookmark")
        }
      }
      Button {
        deferMenuActionPresentation { onShowFilter() }
      } label: {
        Label(String(localized: "Filter"), systemImage: AppIcon.filter)
      }
      .disabled(!isFilterEnabled)
    } label: {
      Image(systemName: AppIcon.more)
    }
  }
}
