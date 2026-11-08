import SwiftUI

struct MangaTranslationSettingsView: View {
  var body: some View {
    Form {
      MangaTranslationSettingsContent()
    }
    .formStyle(.grouped)
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
