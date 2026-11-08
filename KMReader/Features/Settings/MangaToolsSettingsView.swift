import SwiftUI

#if os(iOS) || os(macOS)
  struct MangaToolsSettingsView: View {
    var body: some View {
      Form {
        MangaTranslationSettingsContent()
        #if os(iOS)
          PanelModeSettingsSection()
        #endif
      }
      .formStyle(.grouped)
      .platformNavigationTitle(SettingsSection.mangaTools.title)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button(role: .destructive) {
            MangaTranslationCacheCleaner.clear()
          } label: {
            Image(systemName: AppIcon.delete)
          }
          .accessibilityLabel(Text("Clear Translation Cache"))
        }
      }
    }
  }
#endif
