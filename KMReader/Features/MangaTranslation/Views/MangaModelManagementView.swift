import SwiftUI

struct MangaModelManagementView: View {
  @AppStorage("modelLibrary") private var libraryConfiguration = ModelLibraryConfiguration()

  @State private var catalog: ModelCatalog?
  @State private var downloadedArchives: [ModelArchive] = []
  @State private var statuses: [String: MangaModelStorageStatus] = [:]
  @State private var isLoadingCatalog = false
  @State private var showsCatalogEditor = false
  @State private var catalogURLDraft = ""
  @State private var preparingStorageKey: String?
  @State private var deletingStorageKey: String?
  @State private var archiveToDelete: ModelArchive?
  @State private var showsDeleteConfirmation = false
  @State private var pickingRole: MangaModelRole?

  private var isModelOperationInProgress: Bool {
    preparingStorageKey != nil || deletingStorageKey != nil
  }

  private var availableArchives: [ModelArchive] {
    let downloadedKeys = Set(downloadedArchives.map(\.storageKey))
    return (catalog?.models(for: .mangaOCR) ?? []).filter {
      !downloadedKeys.contains($0.storageKey)
    }
  }

  private var canSaveCatalogURL: Bool {
    let value = catalogURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.host?.isEmpty == false
    else {
      return false
    }
    return true
  }

  var body: some View {
    Form {
      Section(
        footer: Text(
          "Use one model for both roles, or mix a detection model with a different recognition model.")
      ) {
        roleRow(.detector)
        roleRow(.recognizer)
      }

      Section(
        header: Text("Downloaded"),
        footer: Text("Downloaded models remain available when the catalog changes.")
      ) {
        if downloadedArchives.isEmpty {
          Text("No models downloaded")
            .foregroundStyle(.secondary)
        }
        ForEach(downloadedArchives, id: \.storageKey) { archive in
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(archive.name)
              Text(detailText(for: archive))
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(MangaModelRole.capabilityTitle(for: archive))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if preparingStorageKey == archive.storageKey || deletingStorageKey == archive.storageKey {
              LoadingIcon()
            } else {
              Button(role: .destructive) {
                archiveToDelete = archive
                showsDeleteConfirmation = true
              } label: {
                Image(systemName: AppIcon.delete)
              }
              .buttonStyle(.borderless)
              .disabled(isModelOperationInProgress)
            }
          }
        }
      }

      Section(header: Text("Available Models")) {
        if availableArchives.isEmpty && !isLoadingCatalog {
          Text("No additional models in this catalog")
            .foregroundStyle(.secondary)
        }
        ForEach(availableArchives, id: \.storageKey) { archive in
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(archive.name)
              Text(detailText(for: archive))
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(MangaModelRole.capabilityTitle(for: archive))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
              Text(archive.bytes.map { formatBytes(Int64($0)) } ?? String(localized: "Unknown"))
                .font(.caption)
                .foregroundStyle(.secondary)
              Button {
                prepare(archive)
              } label: {
                if preparingStorageKey == archive.storageKey {
                  LoadingIcon()
                } else {
                  Image(systemName: AppIcon.download)
                    .accessibilityLabel(Text("Download & Use"))
                }
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(isModelOperationInProgress)
            }
          }
          .padding(.vertical, 4)
        }
      }

      Section(
        header: HStack {
          Text("Catalog")
          Spacer()
          Button {
            refreshCatalog()
          } label: {
            Label(String(localized: "Refresh Catalog"), systemImage: AppIcon.refresh)
              .labelStyle(.iconOnly)
              .symbolEffect(.pulse, options: .repeating, isActive: isLoadingCatalog)
          }
          .buttonStyle(.borderless)
          .disabled(isLoadingCatalog || isModelOperationInProgress)
        },
        footer: Text("The default catalog is recommended. Custom catalogs must use HTTPS.")
      ) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Catalog URL")
            Text(libraryConfiguration.catalogURL)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer()
          Button(String(localized: "Edit"), action: beginCatalogEdit)
            .buttonStyle(.borderless)
            .disabled(isLoadingCatalog)
        }
      }
    }
    .onAppear {
      catalog = .cached
      reloadDownloadedModels()
      refreshCatalog()
    }
    .sheet(item: $pickingRole) { role in
      MangaModelRolePickerSheet(
        role: role,
        archives: downloadedArchives.filter { MangaModelSet.supports($0, for: role) },
        selectedStorageKey: selectedStorageKey(for: role),
        onSelect: { MangaModelLibrary.select($0, for: role) }
      )
    }
    .sheet(isPresented: $showsCatalogEditor) {
      SheetView(title: String(localized: "Catalog URL"), size: .medium, applyFormStyle: true) {
        Form {
          Section(
            footer: Text("The default catalog is recommended. Custom catalogs must use HTTPS.")
          ) {
            TextField(String(localized: "Catalog URL"), text: $catalogURLDraft)
              .textContentType(.URL)
              .autocorrectionDisabled()
              #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
              #endif
              .onSubmit(saveCatalogURL)
          }
        }
      } controls: {
        Button {
          catalogURLDraft = ModelLibraryConfiguration.defaultCatalogURL
          saveCatalogURL()
        } label: {
          Label(String(localized: "Reset to Default"), systemImage: AppIcon.reset)
            .labelStyle(.iconOnly)
        }
        Button(String(localized: "Save"), action: saveCatalogURL)
          .disabled(!canSaveCatalogURL)
      }
    }
    .alert(String(localized: "Delete Model"), isPresented: $showsDeleteConfirmation) {
      Button(String(localized: "Delete"), role: .destructive) {
        if let archiveToDelete {
          delete(archiveToDelete)
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(archiveToDelete?.name ?? "")
    }
  }

  private func roleRow(_ role: MangaModelRole) -> some View {
    Button {
      pickingRole = role
    } label: {
      HStack {
        Text(role.title)
        Spacer()
        Text(selectedName(for: role))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func selectedStorageKey(for role: MangaModelRole) -> String {
    libraryConfiguration.selectedStorageKeys[role.selectionStorageKey]
      ?? libraryConfiguration.selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] ?? ""
  }

  private func selectedName(for role: MangaModelRole) -> String {
    let key = selectedStorageKey(for: role)
    guard !key.isEmpty,
      let archive = downloadedArchives.first(where: { $0.storageKey == key })
        ?? catalog?.models(for: .mangaOCR).first(where: { $0.storageKey == key })
    else {
      return String(localized: "Not Selected")
    }
    return archive.name
  }

  private func beginCatalogEdit() {
    guard !isLoadingCatalog else { return }
    catalogURLDraft = libraryConfiguration.catalogURL
    showsCatalogEditor = true
  }

  private func cancelCatalogEdit() {
    catalogURLDraft = ""
    showsCatalogEditor = false
  }

  private func saveCatalogURL() {
    guard canSaveCatalogURL else { return }
    libraryConfiguration.catalogURL = catalogURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    libraryConfiguration.catalog = nil
    catalog = nil
    cancelCatalogEdit()
    refreshCatalog()
  }

  private func detailText(for archive: ModelArchive) -> String {
    let version = String(localized: "Version \(archive.version)")
    let size = statuses[archive.storageKey].map { formatBytes($0.totalBytes) }
    return [version, archive.license, size].compactMap { $0 }.joined(separator: " · ")
  }

  private func refreshCatalog() {
    guard !isLoadingCatalog else { return }
    isLoadingCatalog = true
    Task {
      do {
        catalog = try await ModelCatalogService.fetch()
        reloadDownloadedModels()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isLoadingCatalog = false
    }
  }

  private func prepare(_ archive: ModelArchive) {
    guard !isModelOperationInProgress else { return }
    preparingStorageKey = archive.storageKey
    Task {
      do {
        try await MangaTranslationService.shared.prepareModels(archive: archive)
        MangaModelLibrary.select(archive)
        reloadDownloadedModels()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      preparingStorageKey = nil
    }
  }

  private func delete(_ archive: ModelArchive) {
    guard !isModelOperationInProgress else { return }
    deletingStorageKey = archive.storageKey
    Task {
      do {
        try await MangaTranslationService.shared.clearModels(
          storage: ModelStorage.shared,
          archive: archive
        )
        reloadDownloadedModels()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      deletingStorageKey = nil
    }
  }

  private func reloadDownloadedModels() {
    guard let storage = try? ModelStorage.shared else {
      downloadedArchives = []
      statuses = [:]
      return
    }
    MangaModelLibrary.reconcile(storage: storage)
    downloadedArchives = MangaModelLibrary.downloadedArchives()
    statuses = Dictionary(
      downloadedArchives.map {
        ($0.storageKey, MangaModelManager.status(storage: storage.storage(for: $0), archive: $0))
      },
      uniquingKeysWith: { first, _ in first }
    )
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
