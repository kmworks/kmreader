import SwiftUI

struct MangaProviderManagementView: View {
  @AppStorage("mangaTranslation") private var preferences = MangaTranslationPreferences()

  @State private var providers: [MangaProviderConfig] = []
  @State private var editingProvider: MangaProviderConfig?
  @State private var providerToDelete: MangaProviderConfig?
  @State private var showsDeleteConfirmation = false

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
          HStack(spacing: 12) {
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
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button(String(localized: "Edit")) {
              editingProvider = provider
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
              providerToDelete = provider
              showsDeleteConfirmation = true
            } label: {
              Image(systemName: AppIcon.delete)
            }
            .buttonStyle(.borderless)
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

  private func reload() {
    Task {
      do {
        providers = try await MangaProviderLibrary.all(
          database: await DatabaseOperator.databaseIfConfigured()
        )
        preferences = AppConfig.mangaTranslation
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
        preferences = AppConfig.mangaTranslation
        providers = try await MangaProviderLibrary.all(database: database)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
