import SwiftUI

struct MangaTranslationSettingsView: View {
  @State private var model = MangaToolsSettingsModel()

  var body: some View {
    Form {
      MangaTranslationSettingsContent(model: model)
    }
    .formStyle(.grouped)
    .mangaToolsSheets(model: model)
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
    #if os(iOS) || os(macOS)
      .platformNavigationTitle(String(localized: "Manga Translation"))
    #endif
  }
}
