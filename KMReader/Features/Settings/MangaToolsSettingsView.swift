import SwiftUI

#if os(iOS) || os(macOS)
  struct MangaToolsSettingsView: View {
    @State private var model = MangaToolsSettingsModel()

    var body: some View {
      Form {
        MangaTranslationSettingsContent(model: model)
        #if os(iOS)
          PanelModeSettingsSection(model: model)
        #endif
      }
      .formStyle(.grouped)
      .mangaToolsSheets(model: model)
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
