import SwiftUI

struct MangaProviderManagementView: View {
  @AppStorage("mangaTranslation") private var preferences = MangaTranslationPreferences()

  @State private var providers: [MangaProviderConfig] = []
  @State private var editingProvider: MangaProviderConfig?
  @State private var providerToDelete: MangaProviderConfig?
  @State private var showsDeleteConfirmation = false
  @State private var testingProviderID: String?
  @State private var testResultMessage: String?

  private var showsTestResult: Binding<Bool> {
    Binding(
      get: { testResultMessage != nil },
      set: { if !$0 { testResultMessage = nil } }
    )
  }

  var body: some View {
    Form {
      Section(
        header: HStack {
          Text("Providers")
          Spacer()
          Button {
            editingProvider = MangaProviderConfig(baseURL: "", model: "", displayName: "")
          } label: {
            Label(String(localized: "Add Provider"), systemImage: AppIcon.addRow)
          }
          .buttonStyle(.borderless)
        },
        footer: Text(
          "LLM providers receive only OCR text and optional comic metadata. System Translation and page images stay on device."
        )
      ) {
        if SystemTranslationProvider.isAvailable {
          Button {
            preferences.selectedProviderID = ""
          } label: {
            HStack(spacing: 12) {
              Image(systemName: preferences.selectedProviderID.isEmpty ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(preferences.selectedProviderID.isEmpty ? Color.accentColor : Color.secondary)
              VStack(alignment: .leading, spacing: 4) {
                Text(SystemTranslationProvider.displayName)
                Text("Default · On-device")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        if providers.isEmpty {
          Text("No providers configured")
            .foregroundStyle(.secondary)
        }
        ForEach(providers) { provider in
          Button {
            preferences.selectedProviderID = provider.id
          } label: {
            HStack(spacing: 12) {
              Image(systemName: preferences.selectedProviderID == provider.id ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(
                  preferences.selectedProviderID == provider.id ? Color.accentColor : Color.secondary
                )
              VStack(alignment: .leading, spacing: 4) {
                Text(provider.resolvedDisplayName)
                Text(provider.baseURL)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                Text(provider.model)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              if testingProviderID == provider.id {
                Spacer()
                ProgressView()
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          #if os(iOS) || os(macOS)
            .swipeActions(edge: .trailing) {
              providerActions(for: provider)
            }
          #endif
          .contextMenu {
            providerActions(for: provider)
          }
        }
      }
    }
    .onAppear(perform: reload)
    .sheet(item: $editingProvider, onDismiss: reload) { provider in
      MangaProviderEditorView(
        provider: provider,
        isNew: !providers.contains(where: { $0.id == provider.id })
      )
    }
    .alert(String(localized: "Test Provider"), isPresented: showsTestResult) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      if let testResultMessage {
        Text(testResultMessage)
      }
    }
    .alert(String(localized: "Delete Provider"), isPresented: $showsDeleteConfirmation) {
      Button(String(localized: "Delete"), role: .destructive) {
        if let providerToDelete {
          delete(providerToDelete)
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(providerToDelete?.resolvedDisplayName ?? "")
    }
  }

  @ViewBuilder
  private func providerActions(for provider: MangaProviderConfig) -> some View {
    Button {
      test(provider)
    } label: {
      Label(String(localized: "Test Provider"), systemImage: "network")
    }
    .disabled(!provider.isConfigured)

    Button {
      editingProvider = provider
    } label: {
      Label(String(localized: "Edit"), systemImage: AppIcon.edit)
    }

    Button(role: .destructive) {
      providerToDelete = provider
      showsDeleteConfirmation = true
    } label: {
      Label(String(localized: "Delete"), systemImage: AppIcon.delete)
    }
  }

  private func reload() {
    Task {
      do {
        providers = try await MangaProviderLibrary.all(
          database: await DatabaseOperator.databaseIfConfigured()
        )
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func delete(_ provider: MangaProviderConfig) {
    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await MangaProviderLibrary.delete(provider, database: database)
        providers = try await MangaProviderLibrary.all(database: database)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func test(_ provider: MangaProviderConfig) {
    guard testingProviderID == nil else { return }
    testingProviderID = provider.id
    Task {
      do {
        let translations = try await MangaTranslationService.shared.testProvider(
          configuration: provider,
          preferences: preferences
        )
        testResultMessage = translations.joined(separator: " / ")
      } catch {
        testResultMessage =
          (error as? MangaTranslationFailure)?.description ?? error.localizedDescription
      }
      testingProviderID = nil
    }
  }
}
