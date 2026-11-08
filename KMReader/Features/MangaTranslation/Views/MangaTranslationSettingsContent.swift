import SwiftUI

struct MangaTranslationSettingsContent: View {
  @AppStorage("mangaTranslation") private var preferences = MangaTranslationPreferences()

  @State private var modelSheetRole: MangaModelRole?
  @State private var showsProviderManagement = false
  @State private var provider: MangaProviderConfig?
  @State private var detectorArchive: ModelArchive?
  @State private var recognizerArchive: ModelArchive?

  private var usesConfiguredProvider: Bool {
    provider?.isConfigured == true
  }

  private func selectedName(for role: MangaModelRole) -> String {
    let archive = role == .detector ? detectorArchive : recognizerArchive
    return archive?.name ?? String(localized: "Not Selected")
  }

  private var selectedProviderName: String {
    if let provider, provider.isConfigured {
      return provider.resolvedDisplayName
    }
    return SystemTranslationProvider.isAvailable
      ? SystemTranslationProvider.displayName : String(localized: "Not Configured")
  }

  private var privacyDescription: String {
    if usesConfiguredProvider {
      return preferences.includeMetadata
        ? String(localized: "OCR text and comic metadata are sent to the provider; page images are never uploaded.")
        : String(localized: "Only OCR text is sent to the provider; page images are never uploaded.")
    }
    if SystemTranslationProvider.isAvailable {
      return String(
        localized:
          "Recognition and translation run on device with System Translation. Page images never leave the device."
      )
    }
    return String(localized: "Configure an LLM provider to enable translation. Page images never leave the device.")
  }

  var body: some View {
    Group {
      Section(
        header: Text("Manga Translation"),
        footer: Text(
          "Series language metadata is used first. The default source language applies only when metadata is missing.")
      ) {
        Picker(String(localized: "Text Direction"), selection: $preferences.textDirection) {
          Text(String(localized: "Auto")).tag(MangaTranslationTextDirection.auto)
          Text(String(localized: "Horizontal")).tag(MangaTranslationTextDirection.horizontal)
          Text(String(localized: "Vertical")).tag(MangaTranslationTextDirection.vertical)
        }
        Picker(String(localized: "Target Language"), selection: $preferences.targetLanguage) {
          Text(
            String(
              localized:
                "System Language (\(LanguageCodeHelper.displayName(for: MangaTranslationLanguage.systemTarget)))"
            )
          )
          .tag("")
          ForEach(MangaTranslationLanguage.pickerCodes(including: preferences.targetLanguage), id: \.self) { language in
            Text(LanguageCodeHelper.displayName(for: language)).tag(language)
          }
        }
        Picker(String(localized: "Default Source Language"), selection: $preferences.sourceLanguage) {
          ForEach(MangaTranslationLanguage.pickerCodes(including: preferences.sourceLanguage), id: \.self) { language in
            Text(LanguageCodeHelper.displayName(for: language)).tag(language)
          }
        }
        Toggle(isOn: $preferences.includeMetadata) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Include Comic Metadata"))
            Text(String(localized: "Add series, chapter, authors, and genres to the prompt to improve names and tone."))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Section(
        header: Text("Translation Provider"),
        footer: Text(privacyDescription)
      ) {
        Button {
          showsProviderManagement = true
        } label: {
          HStack {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Translation Providers"))
                Text(selectedProviderName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            } icon: {
              Image(systemName: AppIcon.mangaTranslation)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      Section(header: Text("OCR Models")) {
        modelRow(.detector, icon: "text.viewfinder")
        modelRow(.recognizer, icon: "character.textbox")
      }
    }
    .onAppear(perform: reloadConfiguration)
    .sheet(isPresented: $showsProviderManagement, onDismiss: reloadConfiguration) {
      SheetView(title: String(localized: "Translation Providers"), size: .large, applyFormStyle: true) {
        MangaProviderManagementView()
      }
    }
    .sheet(item: $modelSheetRole, onDismiss: reloadConfiguration) { role in
      SheetView(title: role.title, size: .large, applyFormStyle: true) {
        MangaModelManagementView(role: role)
      }
    }
  }

  private func modelRow(_ role: MangaModelRole, icon: String) -> some View {
    Button {
      modelSheetRole = role
    } label: {
      HStack {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(role.title)
            Text(selectedName(for: role))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        } icon: {
          Image(systemName: icon)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func reloadConfiguration() {
    detectorArchive = MangaModelLibrary.selectedArchive(for: .detector)
    recognizerArchive = MangaModelLibrary.selectedArchive(for: .recognizer)
    Task {
      do {
        provider = try await MangaProviderLibrary.current(
          database: await DatabaseOperator.databaseIfConfigured()
        )
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
