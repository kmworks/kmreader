import SwiftUI

struct MangaTranslationSettingsView: View {
  @AppStorage("mangaTranslation") private var preferences = MangaTranslationPreferences()

  @State private var showsModelManagement = false
  @State private var showsProviderManagement = false
  @State private var provider: MangaProviderConfig?
  @State private var archive: ModelArchive?
  @State private var isTesting = false

  private var mangaTranslationEnabled: Binding<Bool> {
    Binding(
      get: { preferences.isEnabled },
      set: { AppConfig.setMangaTranslationEnabled($0) }
    )
  }

  private var usesConfiguredProvider: Bool {
    provider?.isConfigured == true
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
    Form {
      Section {
        Toggle(isOn: mangaTranslationEnabled) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Enable Manga Translation"))
            Text(String(localized: "Show the floating button and translate pages automatically as you read."))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Section(
        header: Text("Languages"),
        footer: Text(
          "Series language metadata is used first. The default source language applies only when metadata is missing.")
      ) {
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
      }

      Section(
        header: HStack {
          Text("Translation")
          Spacer()
          Button {
            testProvider()
          } label: {
            if isTesting {
              Label(String(localized: "Testing…"), systemImage: AppIcon.refresh)
            } else {
              Label(String(localized: "Test Provider"), systemImage: "network")
            }
          }
          .symbolEffect(.pulse, options: .repeating, isActive: isTesting)
          .buttonStyle(.borderless)
          .disabled(isTesting || provider?.isConfigured != true)
        },
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
              Image(systemName: "server.rack")
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Button {
          showsModelManagement = true
        } label: {
          HStack {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Recognition Models"))
                Text(archive?.name ?? String(localized: "Not Selected"))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            } icon: {
              Image(systemName: "cpu")
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Toggle(isOn: $preferences.includeMetadata) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Include Comic Metadata"))
            Text(String(localized: "Add series, chapter, authors, and genres to the prompt to improve names and tone."))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      Section {
        Button(role: .destructive, action: clearTranslations) {
          Label(String(localized: "Clear Translation Cache"), systemImage: AppIcon.delete)
        }
        .buttonStyle(.borderless)
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Manga Translation"))
    .onAppear(perform: reloadConfiguration)
    .sheet(isPresented: $showsProviderManagement, onDismiss: reloadConfiguration) {
      SheetView(title: String(localized: "Translation Providers"), size: .large, applyFormStyle: true) {
        MangaProviderManagementView()
      }
    }
    .sheet(isPresented: $showsModelManagement, onDismiss: reloadConfiguration) {
      SheetView(title: String(localized: "Recognition Models"), size: .large, applyFormStyle: true) {
        MangaModelManagementView()
      }
    }
  }

  private func reloadConfiguration() {
    archive = MangaModelLibrary.selectedArchive
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

  private func clearTranslations() {
    Task {
      do {
        if let database = await DatabaseOperator.databaseIfConfigured() {
          try await MangaTranslationService.shared.clearTranslations(database: database)
        }
        ErrorManager.shared.notify(message: String(localized: "Cache cleared"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func testProvider() {
    guard let provider else { return }
    let resolvedSourceLanguage =
      MangaTranslationLanguage.normalized(preferences.sourceLanguage)
      ?? MangaTranslationLanguage.defaultSource
    let resolvedTargetLanguage =
      MangaTranslationLanguage.normalized(preferences.targetLanguage)
      ?? MangaTranslationLanguage.systemTarget
    isTesting = true
    let testText = resolvedSourceLanguage.hasPrefix("ja") ? "これはテストです。" : "This is a test."
    Task {
      do {
        let translations = try await OpenAICompatibleTranslationProvider().translate(
          segments: [MangaTextSegment(id: 0, text: testText)],
          sourceLanguage: resolvedSourceLanguage,
          targetLanguage: resolvedTargetLanguage,
          metadata: nil,
          configuration: provider
        )
        ErrorManager.shared.notify(message: translations.joined(separator: " / "))
      } catch {
        let message = (error as? MangaTranslationFailure)?.description ?? error.localizedDescription
        ErrorManager.shared.notify(message: message)
      }
      isTesting = false
    }
  }
}
