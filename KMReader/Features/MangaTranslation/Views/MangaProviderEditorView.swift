import SwiftUI

struct MangaProviderEditorView: View {
  private let providerID: String
  private let isNew: Bool

  @Environment(\.dismiss) private var dismiss

  @State private var displayName: String
  @State private var baseURL: String
  @State private var endpointPreset: MangaProviderEndpointPreset
  @State private var model: String
  @State private var apiKey: String
  @State private var availableModels: [String] = []
  @State private var isLoadingModels = false
  @State private var isSaving = false

  init(provider: MangaProviderConfig, isNew: Bool) {
    providerID = provider.id
    self.isNew = isNew
    let initialBaseURL =
      isNew && provider.baseURL.isEmpty
      ? MangaProviderEndpointPreset.openRouter.baseURL ?? "" : provider.baseURL
    _displayName = State(initialValue: provider.displayName)
    _baseURL = State(initialValue: initialBaseURL)
    _endpointPreset = State(initialValue: MangaProviderEndpointPreset(baseURL: initialBaseURL))
    _model = State(initialValue: provider.model)
    _apiKey = State(initialValue: provider.apiKey)
  }

  private var draft: MangaProviderConfig {
    MangaProviderConfig(
      id: providerID,
      baseURL: baseURL,
      model: model,
      displayName: displayName,
      apiKey: apiKey
    )
  }

  private var modelChoices: [String] {
    if model.isEmpty || availableModels.contains(model) {
      return availableModels
    }
    return availableModels + [model]
  }

  private var canSave: Bool {
    draft.isConfigured
  }

  private var canFetchModels: Bool {
    draft.endpoint("models") != nil
      && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    SheetView(
      title: isNew ? String(localized: "Add Provider") : String(localized: "Edit Provider"),
      size: .large,
      applyFormStyle: true
    ) {
      Form {
        Section(
          header: Text("Custom AI API"),
          footer: Text(
            "Enter the API root, including /v1 when required (for example, https://your-server/v1). HTTP and HTTPS are supported. KMReader calls /models and /chat/completions under this URL. Base URL, API Key, and Model are required."
          )
        ) {
          TextField(String(localized: "Display Name"), text: $displayName)
          Picker(String(localized: "Base URL"), selection: $endpointPreset) {
            ForEach(MangaProviderEndpointPreset.allCases) { preset in
              Text(preset.title).tag(preset)
            }
          }
          .onChange(of: endpointPreset) { _, preset in
            if let presetURL = preset.baseURL {
              baseURL = presetURL
            }
          }
          if endpointPreset == .custom {
            TextField(String(localized: "Custom Base URL"), text: $baseURL)
              .textContentType(.URL)
              .autocorrectionDisabled()
              #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
              #endif
          }
          SecureField(String(localized: "API Key"), text: $apiKey)
            .textContentType(.password)
            .autocorrectionDisabled()
        }

        Section(
          header: HStack {
            Text("Model")
            Spacer()
            Button {
              fetchModels()
            } label: {
              if isLoadingModels {
                Label(String(localized: "Loading Models…"), systemImage: AppIcon.refresh)
              } else {
                Label(String(localized: "Fetch Models"), systemImage: AppIcon.refresh)
              }
            }
            .symbolEffect(.pulse, options: .repeating, isActive: isLoadingModels)
            .buttonStyle(.borderless)
            .disabled(isLoadingModels || !canFetchModels)
          },
          footer: Text(
            "Enter the exact model ID expected by your provider, or use Fetch Models after filling in the Base URL and API Key."
          )
        ) {
          HStack(spacing: 8) {
            TextField(String(localized: "Model"), text: $model)
              .autocorrectionDisabled()
            if !availableModels.isEmpty {
              Menu {
                ForEach(modelChoices, id: \.self) { availableModel in
                  Button {
                    model = availableModel
                  } label: {
                    Text(availableModel)
                  }
                }
              } label: {
                Image(systemName: "chevron.up.chevron.down")
                  .accessibilityLabel(Text("Available Models"))
              }
            }
          }
        }
      }
    } controls: {
      Button {
        save()
      } label: {
        if isSaving {
          LoadingIcon()
        } else {
          Label(String(localized: "Save Provider"), systemImage: AppIcon.confirm)
        }
      }
      .disabled(!canSave || isSaving)
    }
  }

  private func fetchModels() {
    guard !isLoadingModels else { return }
    isLoadingModels = true
    Task {
      do {
        availableModels = try await MangaProviderModelService.fetchModels(
          configuration: draft
        )
        let message =
          availableModels.isEmpty
          ? String(localized: "No models returned") : String(localized: "Models loaded")
        ErrorManager.shared.notify(message: message)
      } catch {
        availableModels = []
        let message = (error as? MangaTranslationFailure)?.description ?? error.localizedDescription
        ErrorManager.shared.notify(message: message)
      }
      isLoadingModels = false
    }
  }

  private func save() {
    guard !isSaving else { return }
    isSaving = true
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName = trimmedName.isEmpty ? draft.resolvedDisplayName : trimmedName
    let provider = MangaProviderConfig(
      id: providerID,
      baseURL: baseURL,
      model: model,
      displayName: resolvedName,
      apiKey: apiKey
    )
    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await MangaProviderLibrary.save(provider, select: isNew, database: database)
        dismiss()
      } catch {
        isSaving = false
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
