//
// EpubReaderBottomBar+Menu.swift
//
//

#if os(iOS)
  import SwiftUI

  extension EpubReaderBottomBar {
    @ViewBuilder
    func menuContent() -> some View {
      Button {
        deferMenuActionPresentation { showingChapterSheet = true }
      } label: {
        Label(String(localized: "Contents"), systemImage: "list.bullet")
      }
      .disabled(viewModel.tableOfContents.isEmpty && viewModel.bookmarks.isEmpty)

      Divider()

      Button {
        deferMenuActionPresentation { showingThemeSheet = true }
      } label: {
        Label(String(localized: "Theme"), systemImage: "textformat")
      }

      Button {
        deferMenuActionPresentation { showingSettingsSheet = true }
      } label: {
        Label(String(localized: "Settings"), systemImage: AppIcon.settings)
      }

      Button {
        deferMenuActionPresentation { showingDetailSheet = true }
      } label: {
        Label(String(localized: "Book Info"), systemImage: AppIcon.details)
      }
    }
  }
#endif
